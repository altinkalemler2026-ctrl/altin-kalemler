/**
 * /admin/teacher-reviews görünür başlık testleri (F3 — UI-P3A.1).
 *
 * - Boş kuyrukta görünen h1 Türkçe'dir: "Öğretmen İncelemeleri"
 * - Dolu kuyrukta görünen h1 aynı Türkçe görünür başlıktır
 * - Render edilen gövdede İngilizce "Teacher Review" başlığı kalmaz
 * - Yalnız görünen başlık değişir: veri sorguları ve karar formu
 *   sözleşmesi aynen korunur (karar eylemi çağrılmaz)
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const createClientMock = vi.hoisted(() => vi.fn())
const fromMock = vi.hoisted(() => vi.fn())
const decideTeacherReviewActionMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("./actions", () => ({
  decideTeacherReviewAction: decideTeacherReviewActionMock,
}))

type TableResult = {
  data: unknown[]
  error?: { message: string } | null
}

let tableResults: Record<string, TableResult> = {}

/**
 * Sayfanın beklediği zincir (select → eq/in) ile çalışır; `await`
 * edildiğinde Supabase'in `{ data, error }` şekline çözülür.
 */
function makeBuilder(result: TableResult) {
  const builder: Record<string, unknown> = {}
  const chain = () => builder

  builder.select = chain
  builder.eq = chain
  builder.in = chain
  builder.order = chain
  builder.then = (
    onFulfilled?: (value: unknown) => unknown,
    onRejected?: (reason: unknown) => unknown,
  ) =>
    Promise.resolve({
      data: result.data,
      error: result.error ?? null,
    }).then(onFulfilled, onRejected)

  return builder
}

const RUN = {
  id: "11111111-1111-4111-8111-111111111111",
  staging_question_id: "22222222-2222-4222-8222-222222222222",
  subject_id: "33333333-3333-4333-8333-333333333333",
  status: "human_review_required",
  current_stage: "human_review",
  overall_confidence: 0.7,
  overall_risk_level: "medium",
  human_review_reason: null,
  created_at: "2026-09-01T00:00:00.000Z",
}

const STAGING_QUESTION = {
  id: RUN.staging_question_id,
  question_text: "2 + 2 kaçtır?",
  option_a: "3",
  option_b: "4",
  option_c: "5",
  option_d: "6",
  option_e: null,
  proposed_correct_answer: "B",
  grade_level: 4,
}

const SUBJECT = {
  id: RUN.subject_id,
  name: "Matematik",
}

async function renderPage() {
  const { default: TeacherReviewsPage } = await import("./page")
  const element = await TeacherReviewsPage()
  const { renderToString } = await import("react-dom/server")
  return renderToString(element)
}

function headingCount(html: string): number {
  return html.match(/<h1/g)?.length ?? 0
}

beforeEach(() => {
  tableResults = {}
  createClientMock.mockReset()
  fromMock.mockReset()
  decideTeacherReviewActionMock.mockReset()

  createClientMock.mockImplementation(async () => ({
    from: fromMock,
  }))

  fromMock.mockImplementation((table: string) =>
    makeBuilder(tableResults[table] ?? { data: [] }),
  )
})

describe("TeacherReviewsPage — görünen başlık (F3)", () => {
  it("boş kuyrukta görünen h1 Türkçe'dir; İngilizce başlık render edilmez", async () => {
    tableResults = {
      ai_teacher_review_runs: { data: [] },
    }

    const html = await renderPage()

    expect(html).toContain("Öğretmen İncelemeleri")
    expect(html).not.toContain("Teacher Review")
    expect(headingCount(html)).toBe(1)
    expect(html).toContain("İnsan incelemesi bekleyen soru bulunmuyor.")
  })

  it("dolu kuyrukta görünen h1 Türkçe'dir; karar formu sözleşmesi korunur", async () => {
    tableResults = {
      ai_teacher_review_runs: { data: [RUN] },
      ai_question_staging: { data: [STAGING_QUESTION] },
      subjects: { data: [SUBJECT] },
      ai_teacher_correction_proposals: { data: [] },
      ai_teacher_review_issues: { data: [] },
    }

    const html = await renderPage()

    expect(html).toContain("Öğretmen İncelemeleri")
    expect(html).not.toContain("Teacher Review")
    expect(headingCount(html)).toBe(1)
    expect(html).toContain("Matematik")
    expect(html).toContain("İnsan incelemesi")
    expect(html).toContain("Bekleyen kayıt:")
    expect(decideTeacherReviewActionMock).not.toHaveBeenCalled()
  })
})
