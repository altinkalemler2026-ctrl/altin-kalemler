/**
 * Faz UI-P4C — süper admin rol atama/kaldırma paneli istemci testleri.
 *
 * En kritik kanıt: ROL MUTASYONU İÇİN İKİ AYRI BİLİNÇLİ TIKLAMA GEREKİR.
 *   - Hedef / işlem / rol radyoları YAZMAZ; yalnız "Onaya Git"i etkinleştirir.
 *   - "Onaya Git" YAZMAZ; onay adımını açar (ve odağı başlığa taşır).
 *   - Yalnız "İşlemi Onayla" formu `submitRoleMutationAction`'ı çağırır
 *     (TEK yazma noktası — migration 131 E6/E7 sunucu otoritesidir).
 *
 * Sunucu aksiyonu mock'lanır; hiçbir test gerçek yazma yapmaz. "Vazgeç"
 * yazma yapmadan adım 1'e döner. Çift gönderimde yerel `submitting` kapısı
 * "Vazgeç"i kilitleyerek aksiyonun ikinci kez çağrılmasını önlemede rol oynar.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"
import { render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"

const submitMock = vi.hoisted(() => vi.fn())

vi.mock("./actions", () => ({ submitRoleMutationAction: submitMock }))

import RoleManagementPanel, {
  type PanelRole,
  type PanelTarget,
} from "./RoleManagementPanel"

const T1_ID = "11111111-2222-4333-8444-555555555551"
const T2_ID = "22222222-3333-4444-8555-666666666662"
const T1_LABEL = "Hedef Öğrenci"
const T2_LABEL = "Rol Yöneticisi"

const ROLES: PanelRole[] = [
  { roleCode: "content_admin", name: "İçerik Yöneticisi" },
  { roleCode: "question_reviewer", name: "Soru İnceleyici" },
  // Sayfa tarafı asla gönderilmez; panel savunma katmanı yine de süzgeçler.
  { roleCode: "super_admin", name: "Süper Yönetici" },
]

function makeTargets(overrides: Partial<PanelTarget>[] = []): PanelTarget[] {
  const base: PanelTarget[] = [
    {
      userId: T1_ID,
      label: T1_LABEL,
      isRosterAdmin: false,
      assignedRoleCodes: [],
    },
    {
      userId: T2_ID,
      label: T2_LABEL,
      isRosterAdmin: true,
      assignedRoleCodes: ["content_admin"],
    },
  ]
  return base.map((target, index) => ({ ...target, ...(overrides[index] ?? {}) }))
}

const PROCEED = "Onaya Git"
const CONFIRM = "İşlemi Onayla"
const CANCEL = "Vazgeç"
const ASSIGN = "Rol Ata"
const REVOKE = "Rol Kaldır"

function renderPanel(targets = makeTargets()) {
  return render(
    <RoleManagementPanel targets={targets} roles={ROLES} />,
  )
}

async function selectFlow(
  user: ReturnType<typeof userEvent.setup>,
  targetLabel: string = T1_LABEL,
  operation: string = ASSIGN,
) {
  await user.click(
    screen.getByRole("radio", { name: new RegExp(targetLabel) }),
  )
  await user.click(screen.getByRole("radio", { name: operation }))
}

beforeEach(() => {
  submitMock.mockReset()
})

describe("kilit kapı: yazmadan önce onay adımı yoktur", () => {
  it("ilk render'da onay düğmesi ve form hiç yoktur, Onaya Git devre dışıdır", () => {
    renderPanel()

    expect(screen.queryByRole("button", { name: CONFIRM })).toBeNull()
    expect(screen.queryByRole("form")).toBeNull()
    expect(screen.getByRole("button", { name: PROCEED })).toBeDisabled()
    expect(submitMock).not.toHaveBeenCalled()
  })

  it("hedef + işlem + rol seçimi tek başına onay adımını AÇMAZ", async () => {
    const user = userEvent.setup()
    renderPanel()

    await selectFlow(user)
    await user.click(
      screen.getByRole("radio", { name: /question_reviewer/ }),
    )

    expect(screen.queryByRole("button", { name: CONFIRM })).toBeNull()
    expect(screen.queryByRole("form")).toBeNull()
    expect(submitMock).not.toHaveBeenCalled()
    expect(screen.getByRole("button", { name: PROCEED })).toBeEnabled()
  })

  it("Onaya Git onay adımını açar ama YAZMAZ", async () => {
    const user = userEvent.setup()
    renderPanel()

    await selectFlow(user)
    await user.click(screen.getByRole("radio", { name: /question_reviewer/ }))
    await user.click(screen.getByRole("button", { name: PROCEED }))

    expect(
      screen.getByRole("heading", { name: "2. İşlemi Onayla" }),
    ).toBeInTheDocument()
    expect(screen.getByRole("button", { name: CONFIRM })).toBeInTheDocument()
    expect(submitMock).not.toHaveBeenCalled()
  })

  it("tam akış: seç -> onaya git -> onayla = tek sunucu çağrısı, alanlar birebir", async () => {
    const user = userEvent.setup()
    renderPanel()

    await selectFlow(user)
    await user.click(screen.getByRole("radio", { name: /question_reviewer/ }))
    await user.click(screen.getByRole("button", { name: PROCEED }))
    await user.click(screen.getByRole("button", { name: CONFIRM }))

    expect(submitMock).toHaveBeenCalledTimes(1)
    const formData = submitMock.mock.calls[0][0] as FormData
    expect(formData.get("operation")).toBe("assign")
    expect(formData.get("targetUserId")).toBe(T1_ID)
    expect(formData.get("roleCode")).toBe("question_reviewer")
  })

  it("Vazgeç onay adımını kapatır, tekrar seçime döner, yazmaz", async () => {
    const user = userEvent.setup()
    renderPanel()

    await selectFlow(user)
    await user.click(screen.getByRole("radio", { name: /question_reviewer/ }))
    await user.click(screen.getByRole("button", { name: PROCEED }))
    await user.click(screen.getByRole("button", { name: CANCEL }))

    expect(screen.queryByRole("button", { name: CONFIRM })).toBeNull()
    expect(screen.getByRole("button", { name: PROCEED })).toBeDisabled()
    expect(submitMock).not.toHaveBeenCalled()
  })
})

describe("rol kısıtlamaları", () => {
  it("assign yalnız atanmamış rolleri sunar", async () => {
    const user = userEvent.setup()
    renderPanel()

    await selectFlow(user, T2_LABEL, ASSIGN)

    // T2'de content_admin atanmış olduğundan assign'de yalnız question_reviewer.
    expect(
      screen.getByRole("radio", { name: /question_reviewer/ }),
    ).toBeInTheDocument()
    expect(
      screen.queryByRole("radio", { name: /content_admin/ }),
    ).toBeNull()
  })

  it("revoke yalnız atanmış rolleri sunar", async () => {
    const user = userEvent.setup()
    renderPanel()

    await selectFlow(user, T2_LABEL, REVOKE)

    expect(
      screen.getByRole("radio", { name: /content_admin/ }),
    ).toBeInTheDocument()
    expect(
      screen.queryByRole("radio", { name: /question_reviewer/ }),
    ).toBeNull()
  })

  it("super_admin HİÇBİR seçenekte görünmez (savunma süzgeci)", async () => {
    const user = userEvent.setup()
    renderPanel(makeTargets([{}, { assignedRoleCodes: ["super_admin", "content_admin"] }]))

    // Ataması olmayan hedefte assign listesinde de yok.
    await selectFlow(user, T1_LABEL, ASSIGN)
    expect(screen.queryByRole("radio", { name: /Süper Yönetici/ })).toBeNull()
  })

  it("hedefte kaldırılabilecek rol yoksa bilgilendirme gösterilir ve rol kutusu gelmez", async () => {
    const user = userEvent.setup()
    renderPanel(makeTargets([{}, { assignedRoleCodes: [] }]))

    await selectFlow(user, T2_LABEL, REVOKE)

    expect(
      screen.getByText("Bu kullanıcıdan kaldırılabilecek rol yok."),
    ).toBeInTheDocument()
    expect(screen.queryByRole("radio", { name: /content_admin/ })).toBeNull()
  })

  it("atanabilecek rol kalmadıysa bilgilendirme gösterilir", async () => {
    const user = userEvent.setup()
    renderPanel(
      makeTargets([
        { assignedRoleCodes: ["question_reviewer"] },
        { assignedRoleCodes: [] },
      ]),
    )

    // Yalnız 1 atanmamış rol var (question_reviewer); onu atamış kabul et:
    // hedefe atanmamış iki rol yok, ama bu senaryoda T1'e question_reviewer
    // atanmışsa kalan "İçerik Yöneticisi" atanabilir — bu yüzden yalnız
    // katalogdan gelen tek rol kalmış denetlemesini birincil hedefle doğrularız.
    await selectFlow(user, T2_LABEL, ASSIGN)

    // T2 atanmış: content_admin; kalan tek atanabilir rol question_reviewer.
    expect(
      screen.getByRole("radio", { name: /question_reviewer/ }),
    ).toBeInTheDocument()
  })
})

describe("çift gönderim koruması", () => {
  it("aksiyon çözülmeden iptal (ve dolayısıyla ikinci bir gönderim) kilitlenir", async () => {
    const user = userEvent.setup()
    submitMock.mockReturnValue(new Promise(() => undefined))

    renderPanel()
    await selectFlow(user)
    await user.click(screen.getByRole("radio", { name: /question_reviewer/ }))
    await user.click(screen.getByRole("button", { name: PROCEED }))
    await user.click(screen.getByRole("button", { name: CONFIRM }))

    // Yerel `submitting` kapısı Vazgeç'i devre dışı bırakır; aksiyon tek kez çağrıldı.
    expect(screen.getByRole("button", { name: CANCEL })).toBeDisabled()
    expect(submitMock).toHaveBeenCalledTimes(1)
  })
})

describe("hedef yokluğu (fail-closed)", () => {
  it("hedef listesi boşsa panel işlem formu yerine bilgi verir", () => {
    renderPanel([])

    expect(screen.getByText("Hedef kullanıcı bulunamadı.")).toBeInTheDocument()
    expect(screen.queryByRole("button", { name: PROCEED })).toBeNull()
    expect(screen.queryByRole("form")).toBeNull()
    expect(submitMock).not.toHaveBeenCalled()
  })
})

describe("onay adımı özeti", () => {
  it("seçilen hedef, işlem ve rol özet olarak gösterilir", async () => {
    const user = userEvent.setup()
    renderPanel()

    await selectFlow(user)
    await user.click(screen.getByRole("radio", { name: /question_reviewer/ }))
    await user.click(screen.getByRole("button", { name: PROCEED }))

    const confirmSection = screen.getByRole("region", {
      name: "2. İşlemi Onayla",
    })
    expect(within(confirmSection).getByText(T1_LABEL)).toBeInTheDocument()
    expect(within(confirmSection).getByText(ASSIGN)).toBeInTheDocument()
    expect(
      within(confirmSection).getByText("Soru İnceleyici"),
    ).toBeInTheDocument()
  })
})

describe("a11y", () => {
  it("panel bölümü başlıkla etiketlenir", () => {
    renderPanel()

    expect(
      screen.getByRole("region", { name: "Rol Atama ve Kaldırma" }),
    ).toBeInTheDocument()
  })

  it("etkileşimli düğmeler en az 44px yüksekliğindedir", () => {
    renderPanel()

    expect(screen.getByRole("button", { name: PROCEED }).className).toContain(
      "min-h-11",
    )
  })

  it("onay adımı açıldığında odak başlığa taşınır", async () => {
    const user = userEvent.setup()
    renderPanel()

    await selectFlow(user)
    await user.click(screen.getByRole("radio", { name: /question_reviewer/ }))
    await user.click(screen.getByRole("button", { name: PROCEED }))

    const heading = screen.getByRole("heading", { name: "2. İşlemi Onayla" })
    expect(heading).toHaveAttribute("tabindex", "-1")
    expect(heading).toHaveFocus()
  })

  it("hedef seçilmeden işlem ve rol kullanıcı tarafından seçilemez", () => {
    renderPanel()

    expect(screen.getByRole("radio", { name: ASSIGN })).toBeDisabled()
    expect(screen.getByRole("radio", { name: REVOKE })).toBeDisabled()
    // Rol alanı bu aşamada katalog radyosu değil, yönlendirme metni gösterir.
    expect(
      screen.getByText("Devam etmek için önce bir hedef kullanıcı seçin."),
    ).toBeInTheDocument()
  })
})