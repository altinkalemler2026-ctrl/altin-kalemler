/**
 * StudentHome testleri — ana sayfa.
 *
 * - Gerçek takma ad/sınıf render edilir; sabit sahte isim/yüzde YOK
 * - Günlük hedef gerçek trend verisinden türetilir
 * - Kazanım ilerlemesi gerçek outcome satırlarından türetilir
 * - Hedefli tekrar önerisi gerçek priority DTO'sundan gelir
 * - Veri yok / hata durumları çalışır; ham DB hatası gösterilmez
 * - Lig/XP/seri/bakiye gösterilmez (motorlar hazır değil)
 * - Sınıf sekmesi/seçimi yoktur
 */

import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import {
  DAILY_GOAL_ATTEMPTS,
  REASON_LABELS,
  computeDailyGoal,
  computeOutcomeProgress,
  topRepeatSuggestion,
} from "./StudentHome"
import StudentHome from "./StudentHome"
import type {
  AttemptTrendDay,
  DimensionSummaryRow,
  PriorityTopicDto,
} from "@/lib/analytics/types"

const REFERENCE_NOW = Date.UTC(2026, 8, 4, 12, 0, 0)

function trendRow(day: string, total: number): AttemptTrendDay {
  return {
    day,
    total,
    correct: total,
    wrong: 0,
    blank: 0,
    passTimeout: 0,
    successRate: 100,
    avgTimeMs: 0,
  }
}

function outcomeRow(
  overrides: Partial<DimensionSummaryRow> = {}
): DimensionSummaryRow {
  return {
    scopeType: "outcome",
    scopeKey: "outcome-1",
    displayName: "Kazanım 1",
    subjectId: "subject-1",
    subjectName: "Matematik",
    total: 10,
    correct: 8,
    wrong: 2,
    blank: 0,
    passTimeout: 0,
    repeatTotal: 0,
    repeatCorrect: 0,
    totalTimeMs: 0,
    successRate: 80,
    repeatSuccessRate: 0,
    avgTimeMs: 0,
    lastAttemptedAt: null,
    ...overrides,
  }
}

function priorityTopic(
  overrides: Partial<PriorityTopicDto> = {}
): PriorityTopicDto {
  return {
    topicId: "topic-1",
    topicName: "Kesirler",
    subjectId: "subject-1",
    subjectName: "Matematik",
    totalAttempts: 12,
    successRate: 25,
    repeatTotal: 3,
    repeatSuccessRate: 30,
    avgTimeMs: 0,
    lastAttemptedAt: null,
    evidenceLevel: "medium",
    performanceBand: "WEAK",
    weaknessScore: 50,
    repeatScore: 30,
    recencyScore: 0,
    timeScore: 0,
    priorityScore: 42.5,
    priorityRank: 1,
    reasonCodes: ["LOW_SUCCESS"],
    ...overrides,
  }
}

function renderHome(overrides?: Partial<Parameters<typeof StudentHome>[0]>) {
  return render(
    <StudentHome
      nickname="altinkalem42"
      gradeLevel={7}
      priorities={[]}
      trend7={[]}
      outcomeRows={[]}
      referenceNow={REFERENCE_NOW}
      analyticsError={null}
      {...overrides}
    />
  )
}

describe("StudentHome — kimlik ve eylemler", () => {
  it("gerçek takma ad ve sınıf render edilir", () => {
    renderHome({ nickname: "denizkalemi", gradeLevel: 9 })

    expect(screen.getByText("Hoş geldin, denizkalemi")).toBeInTheDocument()
    expect(screen.getByText("9. Sınıf")).toBeInTheDocument()
  })

  it("sabit Selami veya sahte isim asla görünmez", () => {
    renderHome({ nickname: "gercek-kullanici" })

    expect(screen.queryByText(/Selami/)).not.toBeInTheDocument()
  })

  it("iki ana eylem baglantisi vardir", () => {
    renderHome()

    expect(
      screen.getByRole("link", { name: /Antrenmana Başla/ })
    ).toHaveAttribute("href", "/training")
    expect(
      screen.getByRole("link", { name: /Yarışmaya Katıl/ })
    ).toHaveAttribute("href", "/competition")
  })

  it("sinif sekmesi veya secici yoktur", () => {
    renderHome()

    expect(screen.queryByRole("tablist")).not.toBeInTheDocument()
    expect(screen.queryByRole("combobox")).not.toBeInTheDocument()
  })

  it("lig/XP/seri/bakiye motorlari hazir olmadigindan gosterilmez", () => {
    renderHome()

    expect(screen.queryByText(/Lig sıralaman/)).not.toBeInTheDocument()
    expect(screen.queryByText(/XP/)).not.toBeInTheDocument()
    expect(screen.queryByText(/Seri/)).not.toBeInTheDocument()
    expect(screen.queryByText(/Bakiye/)).not.toBeInTheDocument()
    expect(screen.queryByText(/Yıldız/)).not.toBeInTheDocument()
  })
})

describe("computeDailyGoal", () => {
  it("bugunun gercek trend satirindan hesaplanir", () => {
    const trend = [
      trendRow("2026-09-04", 3),
      trendRow("2026-09-03", 20),
    ]

    const state = computeDailyGoal(trend, REFERENCE_NOW)

    expect(state).toEqual({ attempted: 3, goal: DAILY_GOAL_ATTEMPTS, percent: 30 })
  })

  it("veri yoksa 0 döner; sahte değer üretmez", () => {
    const state = computeDailyGoal([], REFERENCE_NOW)

    expect(state.attempted).toBe(0)
    expect(state.percent).toBe(0)
  })

  it("trend bugünü içermiyorsa 0 sayılır", () => {
    const trend = [trendRow("2026-09-03", 20)]

    expect(computeDailyGoal(trend, REFERENCE_NOW).attempted).toBe(0)
  })
})

describe("computeOutcomeProgress", () => {
  it("gerçek outcome satırlarından ürün eşikleriyle sınıflandırır", () => {
    const rows = [
      outcomeRow({ scopeKey: "o1", successRate: 80, total: 10 }),
      outcomeRow({ scopeKey: "o2", successRate: 50, total: 6 }),
      outcomeRow({ scopeKey: "o3", successRate: 20, total: 4 }),
      outcomeRow({ scopeKey: "o4", successRate: 90, total: 0 }),
    ]

    const progress = computeOutcomeProgress(rows)

    expect(progress).toEqual({
      total: 4,
      withEvidence: 3,
      mastered: 1,
      developing: 1,
      weak: 1,
      insufficient: 1,
      averageSuccessRate: 50,
    })
  })

  it("outcome satırı yoksa null döner", () => {
    expect(computeOutcomeProgress([])).toBeNull()
  })
})

describe("topRepeatSuggestion", () => {
  it("pozitif öncelikli rank-1 topic'i döndürür", () => {
    const suggestion = topRepeatSuggestion([priorityTopic()])

    expect(suggestion?.topicName).toBe("Kesirler")
  })

  it("öncelik skoru 0 ise null döner", () => {
    expect(
      topRepeatSuggestion([priorityTopic({ priorityScore: 0 })])
    ).toBeNull()
  })

  it("liste boşsa null döner", () => {
    expect(topRepeatSuggestion([])).toBeNull()
  })
})

describe("StudentHome — durumlar", () => {
  it("veri yoksa boş durumlar görünür", () => {
    renderHome()

    expect(screen.getByText("Şimdilik tekrar önerisi yok")).toBeInTheDocument()
    expect(screen.getByText("Kazanım verisi yok")).toBeInTheDocument()
    expect(
      screen.getByText(/Bugün henüz soru çözmedin/)
    ).toBeInTheDocument()
  })

  it("gerçek veriyle günlük hedef ve tekrar önerisi render edilir", () => {
    renderHome({
      trend7: [trendRow("2026-09-04", 6)],
      priorities: [
        priorityTopic({
          reasonCodes: ["LOW_SUCCESS", "STALE_TOPIC"],
        }),
      ],
      outcomeRows: [outcomeRow({ successRate: 80, total: 10 })],
    })

    expect(
      screen.getByText("Bugün 6 soru çözdün; hedefin 10 soru.")
    ).toBeInTheDocument()
    expect(screen.getByText("Kesirler")).toBeInTheDocument()
    expect(
      screen.getByText(REASON_LABELS.LOW_SUCCESS)
    ).toBeInTheDocument()
    expect(
      screen.getByText(REASON_LABELS.STALE_TOPIC)
    ).toBeInTheDocument()
    expect(
      screen.getByRole("link", { name: "Bu konuda çalış" })
    ).toHaveAttribute("href", "/training/subject-1")
  })

  it("analytics hatasında güvenli mesaj gösterilir; ham DB hatası sızmaz", () => {
    renderHome({
      analyticsError: "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.",
    })

    const alert = screen.getByRole("alert")

    expect(alert).toHaveTextContent("Çalışma önerileri şu anda yüklenemedi")
    expect(alert).not.toHaveTextContent("relation")
    expect(alert).not.toHaveTextContent("SQL")
    expect(alert).not.toHaveTextContent("postgres")
  })

  it("tekrar önerisi subject yoksa /training'e bağlanır", () => {
    renderHome({
      priorities: [priorityTopic({ subjectId: null })],
    })

    expect(
      screen.getByRole("link", { name: "Bu konuda çalış" })
    ).toHaveAttribute("href", "/training")
  })
})
