/**
 * /admin/curriculum-teaching page security tests (Server Component).
 *
 * - Unauthenticated → /login redirect
 * - curriculum.manage reddi/hata → /dashboard redirect (fail-closed)
 * - Ders + yıl seçimi yoksa liste okunmaz; yönlendirme metni gösterilir
 * - Authorized admin → satır künyeleri render edilir; rozet duruma göre
 * - Onay formları yalnız izinli alanları taşır (schedule_item_id, year,
 *   subject_id, notes, status onay/red butonları)
 * - Veri kaynağı hatası → güvenli mesaj; ham RPC mesajı sızmaz
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())
const redirectMock = vi.hoisted(() =>
  vi.fn((url: string) => {
    throw new Error(`REDIRECT:${url}`)
  }),
)
const hasCurriculumTeachingPermissionMock = vi.hoisted(() => vi.fn())
const listCurriculumTeachingMetaMock = vi.hoisted(() => vi.fn())
const listCurriculumTeachingApprovalsMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/admin/curriculum-teaching", () => ({
  hasCurriculumTeachingPermission: hasCurriculumTeachingPermissionMock,
  listCurriculumTeachingMeta: listCurriculumTeachingMetaMock,
  listCurriculumTeachingApprovals: listCurriculumTeachingApprovalsMock,
}))

async function renderHtml(searchParams: Record<string, string> = {}) {
  const { default: AdminCurriculumTeachingPage } = await import("./page")
  const result = await AdminCurriculumTeachingPage({
    searchParams: Promise.resolve(searchParams),
  })
  const { renderToString } = await import("react-dom/server")
  return renderToString(result)
}

beforeEach(() => {
  getUserMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  hasCurriculumTeachingPermissionMock.mockReset()
  listCurriculumTeachingMetaMock.mockReset()
  listCurriculumTeachingApprovalsMock.mockReset()

  getUserMock.mockResolvedValue({
    data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
  })
  hasCurriculumTeachingPermissionMock.mockResolvedValue(true)
  listCurriculumTeachingMetaMock.mockResolvedValue({
    status: "ok",
    subjects: [{ id: "430903f3-527e-4e12-b7e8-ac0afdb784aa", name: "Matematik" }],
    years: [{ academicYear: "2026-2027" }],
  })
  listCurriculumTeachingApprovalsMock.mockResolvedValue({
    status: "ok",
    items: [],
  })
  createClientMock.mockImplementation(async () => ({
    auth: { getUser: getUserMock },
  }))
})

describe("AdminCurriculumTeachingPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    const { default: AdminCurriculumTeachingPage } = await import("./page")
    await expect(
      AdminCurriculumTeachingPage({ searchParams: Promise.resolve({}) })
    ).rejects.toThrow("REDIRECT:/login")

    expect(hasCurriculumTeachingPermissionMock).not.toHaveBeenCalled()
    expect(listCurriculumTeachingMetaMock).not.toHaveBeenCalled()
  })

  it("curriculum.manage reddi → /dashboard redirect (fail-closed)", async () => {
    hasCurriculumTeachingPermissionMock.mockResolvedValue(false)

    const { default: AdminCurriculumTeachingPage } = await import("./page")
    await expect(
      AdminCurriculumTeachingPage({ searchParams: Promise.resolve({}) })
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(listCurriculumTeachingMetaMock).not.toHaveBeenCalled()
  })

  it("izin RPC çökerse sayfa veri OKUMADAN hatayı yukarı taşır (fail-closed)", async () => {
    hasCurriculumTeachingPermissionMock.mockRejectedValue(
      new Error("permission denied")
    )

    const { default: AdminCurriculumTeachingPage } = await import("./page")
    await expect(
      AdminCurriculumTeachingPage({ searchParams: Promise.resolve({}) })
    ).rejects.toThrow("permission denied")

    expect(listCurriculumTeachingMetaMock).not.toHaveBeenCalled()
  })
})

describe("AdminCurriculumTeachingPage — authorized admin", () => {
  it("ders + yıl seçimi yoksa liste RPC çağrılmaz; seçim yönlendirmesi gösterilir", async () => {
    const html = await renderHtml({})

    expect(listCurriculumTeachingApprovalsMock).not.toHaveBeenCalled()
    expect(html).toContain("Öğretmen Konu Onayı")
    expect(html).toContain(
      "Ders ve akademik yıl seçin; konu onay durumlarını"
    )
    expect(html).toContain("Matematik")
    expect(html).toContain("2026-2027")
  })

  it("ders + yıl seçildiğinde liste RPC'ye iletilir ve satırlar render edilir", async () => {
    listCurriculumTeachingApprovalsMock.mockResolvedValue({
      status: "ok",
      items: [
        {
          scheduleItemId: "a4090000-0000-4000-8000-000000000001",
          scheduleProfileId: "a2000000-0000-4000-8000-0000000000c1",
          profileCode: "TYMM2026-PROF-2026-2027",
          profileName: "TYMM 2026 (9-11) Varsayılan Plan",
          gradeLevel: 9,
          topicName: "MAT.9.1 SAYILAR",
          outcomeText: "Kazanım metni",
          startWeek: 1,
          status: "approved",
          updatedAt: "2026-09-03T10:00:00.000Z",
        },
        {
          scheduleItemId: "a4090000-0000-4000-8000-000000000002",
          gradeLevel: 10,
          topicName: "MAT.10.1",
          startWeek: 5,
          status: null,
          updatedAt: null,
        },
      ],
    })

    const html = await renderHtml({
      subject: "430903f3-527e-4e12-b7e8-ac0afdb784aa",
      year: "2026-2027",
    })

    expect(listCurriculumTeachingApprovalsMock).toHaveBeenCalledWith(
      "430903f3-527e-4e12-b7e8-ac0afdb784aa",
      "2026-2027"
    )
    expect(html).toContain("9<!-- -->. sınıf")
    expect(html).toContain("MAT.9.1 SAYILAR")
    expect(html).toContain("Kazanım metni")
    expect(html).toContain("10<!-- -->. sınıf")
    expect(html).toContain("İşlenmedi")
  })

  it("onay/red formları yalnız izinli alanları taşır", async () => {
    listCurriculumTeachingApprovalsMock.mockResolvedValue({
      status: "ok",
      items: [
        {
          scheduleItemId: "a4090000-0000-4000-8000-000000000001",
          gradeLevel: 9,
          topicName: "MAT.9.1 SAYILAR",
          startWeek: 1,
          status: null,
          updatedAt: null,
        },
      ],
    })

    const html = await renderHtml({
      subject: "430903f3-527e-4e12-b7e8-ac0afdb784aa",
      year: "2026-2027",
    })

    expect(html).toContain("name=\"schedule_item_id\" value=\"a4090000-0000-4000-8000-000000000001\"")
    expect(html).toContain("name=\"academic_year\" value=\"2026-2027\"")
    expect(html).toContain("name=\"subject_id\" value=\"430903f3-527e-4e12-b7e8-ac0afdb784aa\"")
    expect(html).toContain("value=\"approved\"")
    expect(html).toContain("value=\"rejected\"")
    expect(html).toContain("name=\"status\"")
    expect(html).toContain("Not (isteğe bağlı)")

    // Keyfi alan yok: allowlist dışı hiçbir RPC alanı forma/HTML'e düşmez.
    expect(html).not.toContain("before_data")
    expect(html).not.toContain("after_data")
    expect(html).not.toContain("flagged")
  })

  it("veri kaynağı hatasında güvenli mesaj gösterilir; ham mesaj sızmaz", async () => {
    listCurriculumTeachingApprovalsMock.mockResolvedValue({
      status: "error",
      items: [],
    })

    const html = await renderHtml({
      subject: "430903f3-527e-4e12-b7e8-ac0afdb784aa",
      year: "2026-2027",
    })

    expect(html).toContain("Onay işlemi tamamlanamadı")
    expect(html).not.toContain("yetkisi gerekli")
    expect(html).not.toContain("permission denied")
  })
})