// @vitest-environment node
/**
 * Faz 4 dashboard metrik derleyici testleri.
 */

import { describe, expect, it, vi } from "vitest"
import { buildExamTrackBreakdown, loadDashboardMetrics } from "./admin-dashboard"

const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

/** Supabase sorgu zinciri için thenable sahte kurucu. */
function makeQueryMock(result: {
  data: unknown
  error: unknown
  count?: number | null
}) {
  const builder: Record<string, unknown> = {}
  const promise = Promise.resolve(result)
  for (const method of ["select", "order", "limit", "eq", "or", "ilike"]) {
    builder[method] = vi.fn(() => builder)
  }
  builder.then = promise.then.bind(promise)
  builder.catch = promise.catch.bind(promise)
  builder.finally = promise.finally.bind(promise)
  return builder
}

describe("buildExamTrackBreakdown", () => {
  it("okunabilen (null olmayan) değerleri kırılıma katar", () => {
    const breakdown = buildExamTrackBreakdown([
      ["TYT", 5],
      ["AYT", null],
    ])
    expect(breakdown).toEqual({ TYT: 5 })
  })

  it("tümü null ise undefined döner", () => {
    expect(
      buildExamTrackBreakdown([
        ["TYT", null],
        ["AYT", null],
      ])
    ).toBeUndefined()
  })

  it("boş girdi undefined döner", () => {
    expect(buildExamTrackBreakdown([])).toBeUndefined()
  })

  it("tüm değerler okunursa tam kırılım üretir", () => {
    expect(
      buildExamTrackBreakdown([
        ["TYT", 3],
        ["AYT", 7],
      ])
    ).toEqual({ TYT: 3, AYT: 7 })
  })
})

describe("loadDashboardMetrics — sorgu hattı", () => {
  it("veri kaynağı hatasında tüm metrikler null döner (fail-closed)", async () => {
    const builder = makeQueryMock({
      data: null,
      error: { message: "permission denied" },
      count: null,
    })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })

    const metrics = await loadDashboardMetrics()
    expect(metrics.published.value).toBeNull()
    expect(metrics.publishedByExamTrack.value).toBeNull()
    expect(metrics.publishedByExamTrack.breakdown).toBeUndefined()
    expect(metrics.reviewQueue.value).toBeNull()
    expect(metrics.staging.value).toBeNull()
  })

  it("başarılı sayımları metrik kartlarına taşır", async () => {
    const builder = makeQueryMock({ data: null, error: null, count: 5 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })

    const metrics = await loadDashboardMetrics()
    expect(metrics.published.value).toBe(5)
    expect(metrics.publishedByExamTrack.value).toBe(5)
    expect(metrics.publishedByExamTrack.breakdown).toEqual({ TYT: 5, AYT: 5 })
    expect(metrics.reviewQueue.value).toBe(5)
    expect(metrics.staging.value).toBe(5)
  })
})
