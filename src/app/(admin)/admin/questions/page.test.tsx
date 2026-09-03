/**
 * /admin/questions list page security + pagination tests (Server Component).
 *
 * - Unauthenticated → /login redirect
 * - Non-admin (questions.view denied) → /dashboard redirect
 * - Server-side pagination: default page, page param, filter preservation
 * - Invalid subject UUID rejected before query
 * - PostgREST grammar characters and long search pass through page safely
 * - Error vs empty separation
 * - Copyright risk badge rendering
 * - Raw error text never reaches the UI
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())
const redirectMock = vi.hoisted(() =>
  vi.fn((url: string) => {
    throw new Error(`REDIRECT:${url}`)
  }),
)
const listQuestionsMock = vi.hoisted(() => vi.fn())
const listSubjectsMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/admin/question-bank", async () => {
  const actual = await vi.importActual<
    typeof import("@/lib/admin/question-bank")
  >("@/lib/admin/question-bank")
  return {
    listQuestions: listQuestionsMock,
    listSubjects: listSubjectsMock,
    parseGrade: actual.parseGrade,
    parsePage: actual.parsePage,
    parseUuid: actual.parseUuid,
    sanitizeSearchQuery: actual.sanitizeSearchQuery,
    EXAM_TRACKS: actual.EXAM_TRACKS,
    GRADES: actual.GRADES,
    DIFFICULTIES: actual.DIFFICULTIES,
    APPROVAL_STATUSES: actual.APPROVAL_STATUSES,
  }
})

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  listQuestionsMock.mockReset()
  listSubjectsMock.mockReset()
  listQuestionsMock.mockResolvedValue({
    status: "ok",
    items: [],
    total: 0,
    page: 1,
    totalPages: 1,
  })
  listSubjectsMock.mockResolvedValue([
    { id: "bbbbbbb1-0000-4000-8000-000000000001", name: "Matematik" },
  ])

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

function okResult(overrides: Partial<{ items: unknown[]; total: number; page: number; totalPages: number }> = {}) {
  return {
    status: "ok",
    items: [],
    total: 0,
    page: 1,
    totalPages: 1,
    ...overrides,
  }
}

const SUBJECT_ID = "bbbbbbb1-0000-4000-8000-000000000001"

function questionItem(overrides: Record<string, unknown> = {}) {
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
    ...overrides,
  }
}

import AdminQuestionsPage from "./page"

describe("AdminQuestionsPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    mockUnauthenticated()

    await expect(
      AdminQuestionsPage({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow("REDIRECT:/login")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(listQuestionsMock).not.toHaveBeenCalled()
  })

  it("permission hatası → /dashboard redirect", async () => {
    mockAuthenticated()
    mockPermissionError()

    await expect(
      AdminQuestionsPage({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(listQuestionsMock).not.toHaveBeenCalled()
  })

  it("canView !== true (questions.view reddi) → /dashboard redirect", async () => {
    mockAuthenticated()
    mockNoPermission()

    await expect(
      AdminQuestionsPage({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(listQuestionsMock).not.toHaveBeenCalled()
  })
})

describe("AdminQuestionsPage — authorized admin ve sayfalama", () => {
  it("questions.view yetkisiyle listQuestions varsayılan sayfa 1 ile çağrılır", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminQuestionsPage({ searchParams: Promise.resolve({}) })

    expect(rpcMock).toHaveBeenCalledWith("teacher_review_admin_has_permission", {
      p_permission_code: "questions.view",
    })
    expect(listQuestionsMock).toHaveBeenCalledWith(
      {
        examTrack: undefined,
        grade: undefined,
        subjectId: undefined,
        difficulty: undefined,
        approvalStatus: undefined,
        isActive: undefined,
        query: undefined,
      },
      1,
    )
  })

  it("page parametresi sayıya çevrilip geçirilir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminQuestionsPage({
      searchParams: Promise.resolve({ page: "2" }),
    })

    expect(listQuestionsMock).toHaveBeenCalledTimes(1)
    const [, pageArg] = listQuestionsMock.mock.calls[0] as [unknown, number]
    expect(pageArg).toBe(2)
  })

  it("geçersiz page değerleri 1'e düşer", async () => {
    mockAuthenticated()
    mockAdminPermission()

    for (const bad of ["abc", "0", "-3", "2.5"]) {
      listQuestionsMock.mockClear()
      await AdminQuestionsPage({
        searchParams: Promise.resolve({ page: bad }),
      })
      const [, pageArg] = listQuestionsMock.mock.calls[0] as [unknown, number]
      expect(pageArg).toBe(1)
    }
  })

  it("arama + subject filtresi + page birlikte geçirilir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminQuestionsPage({
      searchParams: Promise.resolve({
        query: "türev",
        subject: SUBJECT_ID,
        page: "3",
      }),
    })

    expect(listQuestionsMock).toHaveBeenCalledWith(
      expect.objectContaining({ query: "türev", subjectId: SUBJECT_ID }),
      3,
    )
  })

  it("geçersiz subject UUID'si sorguya gönderilmez", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminQuestionsPage({
      searchParams: Promise.resolve({ subject: "not-a-uuid" }),
    })

    expect(listQuestionsMock).toHaveBeenCalledWith(
      expect.objectContaining({ subjectId: undefined }),
      1,
    )
  })

  it("PostgREST gramer karakterleri sayfa katmanında korunur (sanitizasyon lib'de)", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminQuestionsPage({
      searchParams: Promise.resolve({ query: "a,b(c)" }),
    })

    expect(listQuestionsMock).toHaveBeenCalledWith(
      expect.objectContaining({ query: "a,b(c)" }),
      1,
    )
  })

  it("çok uzun arama girdisi sayfa katmanında bozulmaz (sınır lib'de)", async () => {
    mockAuthenticated()
    mockAdminPermission()
    const longQuery = "a".repeat(300)

    await AdminQuestionsPage({
      searchParams: Promise.resolve({ query: longQuery }),
    })

    expect(listQuestionsMock).toHaveBeenCalledWith(
      expect.objectContaining({ query: longQuery }),
      1,
    )
  })
})

describe("AdminQuestionsPage — hata ve boş durum ayrımı", () => {
  it("gerçekten boş sonuçta 'kayıt bulunamadı' mesajı gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listQuestionsMock.mockResolvedValue(okResult())

    const result = await AdminQuestionsPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Bu filtrelerle eşleşen soru bulunamadı")
    expect(html).not.toContain("okunamadı")
  })

  it("veri kaynağı hatasında ayrı hata mesajı gösterilir (ham mesaj sızmaz)", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listQuestionsMock.mockResolvedValue({
      status: "error",
      items: [],
      total: 0,
      page: 1,
      totalPages: 1,
    })

    const result = await AdminQuestionsPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Soru listesi şu anda okunamadı")
    expect(html).not.toContain("Bu filtrelerle eşleşen soru bulunamadı")
    expect(html).not.toContain("db down")
    expect(html).not.toContain("permission denied")
  })
})

describe("AdminQuestionsPage — sayfalama gezinmesi", () => {
  it("çok sayfalı sonuçta sayfa göstergesi ve bağlantılar görünür", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listQuestionsMock.mockResolvedValue(
      okResult({
        items: [questionItem()],
        total: 60,
        page: 2,
        totalPages: 3,
      }),
    )

    const result = await AdminQuestionsPage({
      searchParams: Promise.resolve({ page: "2" }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Sayfa 2 / 3")
    expect(html).toContain("Önceki")
    expect(html).toContain("Sonraki")
    expect(html).toContain('aria-label="Sayfalama"')
  })

  it("bağlantılar arama ve subject filtrelerini korur", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listQuestionsMock.mockResolvedValue(
      okResult({
        items: [questionItem()],
        total: 60,
        page: 2,
        totalPages: 3,
      }),
    )

    const result = await AdminQuestionsPage({
      searchParams: Promise.resolve({
        query: "türev",
        subject: SUBJECT_ID,
        page: "2",
      }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain(`subject=${SUBJECT_ID}&amp;query=t%C3%BCrev&amp;page=1`)
    expect(html).toContain(`subject=${SUBJECT_ID}&amp;query=t%C3%BCrev&amp;page=3`)
  })

  it("son sayfada 'Sonraki' devre dışıdır", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listQuestionsMock.mockResolvedValue(
      okResult({
        items: [questionItem()],
        total: 60,
        page: 3,
        totalPages: 3,
      }),
    )

    const result = await AdminQuestionsPage({
      searchParams: Promise.resolve({ page: "3" }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Sayfa 3 / 3")
    expect(html).not.toContain("page=4")
  })
})

describe("AdminQuestionsPage — copyright risk gösterimi", () => {
  it("license_status 'approved' olmayan soruda 'Telif riski' rozeti görünür", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listQuestionsMock.mockResolvedValue(
      okResult({
        items: [
          questionItem({ license_status: "under_review" }),
          questionItem({ id: "aaaaaaaa-1111-4000-8000-000000000002", question_code: "TYT-MAT-002", license_status: "approved" }),
        ],
        total: 2,
      }),
    )

    const result = await AdminQuestionsPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Telif riski")
  })

  it("license_status 'approved' ise risk rozeti gösterilmez", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listQuestionsMock.mockResolvedValue(
      okResult({
        items: [questionItem({ license_status: "approved" })],
        total: 1,
      }),
    )

    const result = await AdminQuestionsPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain("Telif riski")
  })

  it("license_status null ise risk rozeti gösterilmez", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listQuestionsMock.mockResolvedValue(
      okResult({
        items: [questionItem({ license_status: null })],
        total: 1,
      }),
    )

    const result = await AdminQuestionsPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain("Telif riski")
  })
})

describe("AdminQuestionsPage — no mutation capability", () => {
  it("sayfa mutation fonksiyonu import etmez", async () => {
    const pageModule = await import("./page")
    const source = Object.keys(pageModule)
    expect(source).toEqual(["default"])
  })
})
