/**
 * /admin/questions/[id] detail page security tests (Server Component).
 *
 * - Unauthenticated → /login redirect
 * - Non-admin (questions.view denied) → /dashboard redirect
 * - Authorized admin + found question → detail renders metadata and options
 * - Authorized admin + not found → "Soru bulunamadı" message
 * - Authorized admin + data source error → distinct "okunamadı" message
 * - DTO allowlist enforced: no PII/secrets in rendered output
 * - Edit form is permission-gated: rendered ONLY for questions.edit,
 *   fail-closed (never rendered for unauthorized admins)
 * - Publication controls gated by questions.approve/ai.manage and the
 *   server-side readiness result
 */

import { beforeEach, describe, expect, it, vi } from "vitest"
import { QUESTION_PUBLICATION_MESSAGES } from "@/lib/admin/question-edit-errors"

const getUserMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())
const redirectMock = vi.hoisted(() =>
  vi.fn((url: string) => {
    throw new Error(`REDIRECT:${url}`)
  }),
)
const getQuestionDetailMock = vi.hoisted(() => vi.fn())
const hasPermissionMock = vi.hoisted(() => vi.fn())
const readinessMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("next/cache", () => ({
  revalidatePath: vi.fn(),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/admin/question-bank", () => ({
  getQuestionDetail: getQuestionDetailMock,
  listQuestions: vi.fn(),
  listSubjects: vi.fn(),
  parseGrade: vi.fn(),
  parsePage: vi.fn(),
  parseSort: vi.fn(),
  parseUuid: vi.fn(),
  sanitizeSearchQuery: vi.fn(),
}))

vi.mock("@/lib/admin/question-edit", () => ({
  hasAdminPermission: hasPermissionMock,
  getPublicationReadiness: readinessMock,
}))

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  getQuestionDetailMock.mockReset()
  hasPermissionMock.mockReset()
  readinessMock.mockReset()
  getQuestionDetailMock.mockResolvedValue({ status: "ok", item: null })
  hasPermissionMock.mockResolvedValue(false)
  readinessMock.mockResolvedValue({
    status: "ok",
    currentIsActive: false,
    canActivate: false,
    blockers: [],
    warnings: [],
  })

  createClientMock.mockImplementation(async () => ({
    auth: { getUser: getUserMock },
    rpc: rpcMock,
  }))
})

function mockAuthenticated() {
  getUserMock.mockResolvedValue({
    data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
  })
}

function mockUnauthenticated() {
  getUserMock.mockResolvedValue({ data: { user: null } })
}

function mockAdminPermission() {
  rpcMock.mockResolvedValue({ data: true, error: null })
}

function mockNoPermission() {
  rpcMock.mockResolvedValue({ data: false, error: null })
}

function mockPermissionError() {
  rpcMock.mockResolvedValue({ data: null, error: { message: "permission denied" } })
}

function questionDetail(overrides: Record<string, unknown> = {}) {
  return {
    id: "aaaaaaaa-1111-4000-8000-000000000001",
    question_code: "TYT-MAT-001",
    question_text: "1 + 1 kaç eder?",
    exam_track: "TYT",
    grade_level: 7,
    difficulty: "easy",
    approval_status: "approved",
    is_active: true,
    correct_answer: "B",
    created_at: "2026-08-01T10:00:00.000Z",
    subject_name: "Matematik",
    license_status: "approved",
    option_a: "1",
    option_b: "2",
    option_c: "3",
    option_d: "4",
    option_e: "5",
    quality_level: "high",
    ownership_status: "owned",
    estimated_solve_time_seconds: 60,
    subject_id: "bbbbbbb1-0000-4000-8000-000000000001",
    ...overrides,
  }
}

async function renderPage(options: {
  question?: Record<string, unknown> | null
  status?: "ok" | "error"
} = {}) {
  const question =
    options.question === undefined ? questionDetail() : options.question
  getQuestionDetailMock.mockResolvedValue({
    status: options.status ?? "ok",
    item: question,
  })

  const { default: AdminQuestionDetailPage } = await import("./page")
  const result = await AdminQuestionDetailPage({
    params: Promise.resolve({ id: "q1" }),
    searchParams: Promise.resolve({}),
  })

  const { renderToString } = await import("react-dom/server")
  return renderToString(result)
}

describe("AdminQuestionDetailPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    mockUnauthenticated()

    const { default: AdminQuestionDetailPage } = await import("./page")
    await expect(
      AdminQuestionDetailPage({
        params: Promise.resolve({ id: "q1" }),
        searchParams: Promise.resolve({}),
      }),
    ).rejects.toThrow("REDIRECT:/login")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(getQuestionDetailMock).not.toHaveBeenCalled()
  })

  it("permission hatası → /dashboard redirect", async () => {
    mockAuthenticated()
    mockPermissionError()

    const { default: AdminQuestionDetailPage } = await import("./page")
    await expect(
      AdminQuestionDetailPage({
        params: Promise.resolve({ id: "q1" }),
        searchParams: Promise.resolve({}),
      }),
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(getQuestionDetailMock).not.toHaveBeenCalled()
  })

  it("canView !== true (questions.view reddi) → /dashboard redirect", async () => {
    mockAuthenticated()
    mockNoPermission()

    const { default: AdminQuestionDetailPage } = await import("./page")
    await expect(
      AdminQuestionDetailPage({
        params: Promise.resolve({ id: "q1" }),
        searchParams: Promise.resolve({}),
      }),
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(getQuestionDetailMock).not.toHaveBeenCalled()
  })
})

describe("AdminQuestionDetailPage — authorized admin", () => {
  it("questions.view yetkisiyle getQuestionDetail çağrılır ve künye render edilir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    const html = await renderPage()

    expect(rpcMock).toHaveBeenCalledWith("teacher_review_admin_has_permission", {
      p_permission_code: "questions.view",
    })
    expect(getQuestionDetailMock).toHaveBeenCalledWith("q1")

    expect(html).toContain("TYT-MAT-001")
    expect(html).toContain("1 + 1 kaç eder?")
    expect(html).toContain("Lisans durumu")
  })

  it("questions.edit izni olmayan admende düzenleme formu HİÇ render edilmez (fail-closed)", async () => {
    mockAuthenticated()
    mockAdminPermission()
    hasPermissionMock.mockResolvedValue(false)

    const html = await renderPage()

    expect(html).not.toContain("Soruyu Düzenle")
    expect(html).not.toContain('name="questionText"')
    expect(html).not.toContain("Yayın Kontrolü")
  })

  it("questions.edit izni olan admende düzenleme formu render edilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    hasPermissionMock.mockImplementation(async (code: string) => {
      return code === "questions.edit"
    })

    const html = await renderPage()

    expect(hasPermissionMock).toHaveBeenCalledWith("questions.edit")
    expect(html).toContain("Soruyu Düzenle")
    expect(html).toContain('name="questionText"')
    expect(html).toContain('name="correctAnswer"')
    expect(html).toContain('name="optionA"')
    // E seçeneği isteğe bağlıdır ve boş bırakılmasının sonucu belirtilir.
    expect(html).toContain("isteğe bağlı")
    expect(html).toContain("boş bırakılırsa kayıttan kaldırılır")
  })

  it("questions.approve izni olan admende yayın kontrolü readiness'e göre render edilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    hasPermissionMock.mockImplementation(async (code: string) => {
      return code === "questions.approve"
    })
    readinessMock.mockResolvedValue({
      status: "ok",
      currentIsActive: false,
      canActivate: false,
      blockers: [{ code: "question_not_approved", message: "onaylı değil" }],
      warnings: [],
    })

    const html = await renderPage()

    expect(readinessMock).toHaveBeenCalledWith("q1")
    expect(html).toContain("Yayın Kontrolü")
    expect(html).toContain("onaylı değil")
    // Yayına uygun değil: aktivasyon düğmesi devre dışı.
    expect(html).toMatch(/disabled[^>]*>\s*Öğrencilere Yayınla|Öğrencilere Yayınla[\s\S]{0,200}disabled/)
  })

  it("readiness PASS ise aktivasyon düğmesi etkindir; geri çekme devre dışıdır", async () => {
    mockAuthenticated()
    mockAdminPermission()
    hasPermissionMock.mockImplementation(async (code: string) => {
      return code === "questions.approve"
    })
    readinessMock.mockResolvedValue({
      status: "ok",
      currentIsActive: false,
      canActivate: true,
      blockers: [],
      warnings: [],
    })

    const html = await renderPage()

    expect(html).toContain(QUESTION_PUBLICATION_MESSAGES.readyTitle)
    const activateIdx = html.indexOf("Öğrencilere Yayınla")
    const deactivateIdx = html.indexOf("Yayından Geri Çek")
    expect(activateIdx).toBeGreaterThan(-1)
    expect(deactivateIdx).toBeGreaterThan(-1)
    // Aktivasyon düğmesi disabled içermez; geri çekme içerir.
    const activateButton = html.slice(
      Math.max(0, activateIdx - 600),
      activateIdx
    )
    const deactivateButton = html.slice(
      Math.max(0, deactivateIdx - 600),
      deactivateIdx
    )
    expect(activateButton).not.toContain("disabled")
    expect(deactivateButton).toContain("disabled")
  })

  it("readiness okunamazsa yayına özel 'okunamadı' mesajı gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    hasPermissionMock.mockResolvedValue(true)
    readinessMock.mockResolvedValue({
      status: "error",
      currentIsActive: null,
      canActivate: false,
      blockers: [],
      warnings: [],
    })

    const html = await renderPage()

    expect(html).toContain(
      "Yayın uygunluk durumu şu anda okunamadı"
    )
  })

  it("questions.edit yetkisi olan ama onay yetkisi olmayan admende salt-okunur yayın durumu özeti gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    hasPermissionMock.mockImplementation(async (code: string) => {
      return code === "questions.edit"
    })
    readinessMock.mockResolvedValue({
      status: "ok",
      currentIsActive: false,
      canActivate: false,
      blockers: [{ code: "question_not_approved", message: "onaylı değil" }],
      warnings: [],
    })

    const html = await renderPage()

    expect(html).toContain("Yayın Durumu")
    expect(html).toContain("onaylı değil")
    expect(html).toContain("Yayın/geri çekme işlemleri için onay yetkisi gerekir")
    // Yayın kontrolleri (butonlar) YOK: onay yetkisi olmadan hiç render edilmez.
    expect(html).not.toContain("Öğrencilere Yayınla")
    expect(html).not.toContain("Yayından Geri Çek")
  })

  it("flash parametreleri güvenli banner olarak render edilir (ham mesaj URL'den aynen gelir ama kaçışlanır)", async () => {
    mockAuthenticated()
    mockAdminPermission()
    hasPermissionMock.mockResolvedValue(false)

    getQuestionDetailMock.mockResolvedValue({
      status: "ok",
      item: questionDetail(),
    })
    const { default: AdminQuestionDetailPage } = await import("./page")
    const result = await AdminQuestionDetailPage({
      params: Promise.resolve({ id: "q1" }),
      searchParams: Promise.resolve({
        ok: "Soru güncellendi.",
        error: "Soru bulunamadı; sayfayı yenileyip tekrar deneyin.",
      }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    // error banner'ı önceliklidir: error varken ok banner'ı gösterilmez.
    expect(html).toMatch(/role="alert"/)
    expect(html).toContain("Soru bulunamadı; sayfayı yenileyip tekrar deneyin.")
    expect(html).not.toMatch(/role="status"/)
    expect(html).not.toContain("Soru güncellendi.")
  })
})

describe("AdminQuestionDetailPage — hata/bulunamadı ayrımı", () => {
  it("soru bulunamadığında 'bulunamadı' mesajı gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    const html = await renderPage({ question: null })

    expect(html).toContain("Soru bulunamadı")
    expect(html).not.toContain("okunamadı")
  })

  it("veri kaynağı hatasında ayrı hata mesajı gösterilir (ham mesaj sızmaz)", async () => {
    mockAuthenticated()
    mockAdminPermission()

    const html = await renderPage({ status: "error" })

    expect(html).toContain("Soru bilgileri şu anda okunamadı")
    expect(html).not.toContain("Soru bulunamadı")
    expect(html).not.toContain("db down")
    expect(html).not.toContain("permission denied")
  })
})

describe("AdminQuestionDetailPage — PII/secret non-leakage", () => {
  it("hiçbir sensitive alan detail sonucundan geçmez", async () => {
    mockAuthenticated()
    mockAdminPermission()
    hasPermissionMock.mockImplementation(async (code: string) => {
      return code === "questions.edit"
    })

    const html = await renderPage({
      question: questionDetail({
        nickname: "ANA-NICK-GIZLI",
        email: "soru-detay-pii@test.local",
        solution: "ANA-COZUM-GIZLI",
        explanation: "ANA-ACIKLAMA-GIZLI",
      }),
    })

    expect(html).not.toContain("ANA-NICK-GIZLI")
    expect(html).not.toContain("soru-detay-pii@test.local")
    expect(html).not.toContain("ANA-COZUM-GIZLI")
    expect(html).not.toContain("ANA-ACIKLAMA-GIZLI")
    expect(html).not.toContain("nickname")
    expect(html).not.toContain("solution")
    expect(html).not.toContain("explanation")
  })
})
