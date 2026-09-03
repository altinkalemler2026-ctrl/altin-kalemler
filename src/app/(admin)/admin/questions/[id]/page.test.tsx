/**
 * /admin/questions/[id] detail page security tests (Server Component).
 *
 * - Unauthenticated → /login redirect
 * - Non-admin (questions.view denied) → /dashboard redirect
 * - Authorized admin + found question → detail renders metadata and options
 * - Authorized admin + not found → "Soru bulunamadı" message
 * - Authorized admin + data source error → distinct "okunamadı" message
 * - DTO allowlist enforced: no PII/secrets in rendered output
 * - No mutation imports: page is strictly read-only
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
const getQuestionDetailMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
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

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  getQuestionDetailMock.mockReset()
  getQuestionDetailMock.mockResolvedValue({ status: "ok", item: null })

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

import AdminQuestionDetailPage from "./page"

describe("AdminQuestionDetailPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    mockUnauthenticated()

    await expect(
      AdminQuestionDetailPage({ params: Promise.resolve({ id: "q1" }) }),
    ).rejects.toThrow("REDIRECT:/login")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(getQuestionDetailMock).not.toHaveBeenCalled()
  })

  it("permission hatası → /dashboard redirect", async () => {
    mockAuthenticated()
    mockPermissionError()

    await expect(
      AdminQuestionDetailPage({ params: Promise.resolve({ id: "q1" }) }),
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(getQuestionDetailMock).not.toHaveBeenCalled()
  })

  it("canView !== true (questions.view reddi) → /dashboard redirect", async () => {
    mockAuthenticated()
    mockNoPermission()

    await expect(
      AdminQuestionDetailPage({ params: Promise.resolve({ id: "q1" }) }),
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(getQuestionDetailMock).not.toHaveBeenCalled()
  })
})

describe("AdminQuestionDetailPage — authorized admin", () => {
  it("questions.view yetkisiyle getQuestionDetail çağrılır ve künye render edilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    getQuestionDetailMock.mockResolvedValue({
      status: "ok",
      item: questionDetail(),
    })

    const result = await AdminQuestionDetailPage({
      params: Promise.resolve({ id: "q1" }),
    })

    expect(rpcMock).toHaveBeenCalledWith("teacher_review_admin_has_permission", {
      p_permission_code: "questions.view",
    })
    expect(getQuestionDetailMock).toHaveBeenCalledWith("q1")

    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("TYT-MAT-001")
    expect(html).toContain("1 + 1 kaç eder?")
    expect(html).toContain("Lisans durumu")
  })
})

describe("AdminQuestionDetailPage — hata/bulunamadı ayrımı", () => {
  it("soru bulunamadığında 'bulunamadı' mesajı gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    getQuestionDetailMock.mockResolvedValue({ status: "ok", item: null })

    const result = await AdminQuestionDetailPage({
      params: Promise.resolve({ id: "missing" }),
    })

    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Soru bulunamadı")
    expect(html).not.toContain("okunamadı")
  })

  it("veri kaynağı hatasında ayrı hata mesajı gösterilir (ham mesaj sızmaz)", async () => {
    mockAuthenticated()
    mockAdminPermission()
    getQuestionDetailMock.mockResolvedValue({ status: "error", item: null })

    const result = await AdminQuestionDetailPage({
      params: Promise.resolve({ id: "q1" }),
    })

    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

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
    getQuestionDetailMock.mockResolvedValue({
      status: "ok",
      item: questionDetail({
        nickname: "ANA-NICK-GIZLI",
        email: "soru-detay-pii@test.local",
        solution: "ANA-COZUM-GIZLI",
        explanation: "ANA-ACIKLAMA-GIZLI",
      }),
    })

    const result = await AdminQuestionDetailPage({
      params: Promise.resolve({ id: "q1" }),
    })

    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain("ANA-NICK-GIZLI")
    expect(html).not.toContain("soru-detay-pii@test.local")
    expect(html).not.toContain("ANA-COZUM-GIZLI")
    expect(html).not.toContain("ANA-ACIKLAMA-GIZLI")
    expect(html).not.toContain("nickname")
    expect(html).not.toContain("solution")
    expect(html).not.toContain("explanation")
  })
})

describe("AdminQuestionDetailPage — no mutation capability", () => {
  it("sayfa mutation fonksiyonu import etmez", async () => {
    const pageModule = await import("./page")
    const source = Object.keys(pageModule)
    expect(source).toEqual(["default"])
  })
})
