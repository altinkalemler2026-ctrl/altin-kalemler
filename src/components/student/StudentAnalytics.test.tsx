/**
 * StudentAnalytics component testleri.
 *
 * Kapsam: boş durum, güçlü/gelişen/öncelikli/yetersiz-veri bölümleri,
 * "Bugün ne çalışmalıyım?" kartı, trend özeti, neden kodu çevirileri,
 * semantik başlık erişilebilirliği.
 */

import type { ReactNode } from "react"
import { render, screen, within } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

vi.mock("next/link", () => ({
  default: ({
    href,
    children,
    ...rest
  }: {
    href: string
    children: ReactNode
  }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}))

import type {
  AttemptTrendDay,
  PriorityTopicDto,
} from "@/lib/analytics/types"
import StudentAnalytics from "./StudentAnalytics"

function topic(overrides: Partial<PriorityTopicDto>): PriorityTopicDto {
  return {
    topicId: "bbbbbbb2-0000-4000-8000-000000000001",
    topicName: "Kümeler",
    subjectId: "bbbbbbb1-0000-4000-8000-000000000001",
    subjectName: "Matematik",
    totalAttempts: 10,
    successRate: 80,
    repeatTotal: 0,
    repeatSuccessRate: 0,
    avgTimeMs: 6000,
    lastAttemptedAt: "2026-08-12T10:00:00.000Z",
    evidenceLevel: "high",
    performanceBand: "STRONG",
    weaknessScore: 10,
    repeatScore: 0,
    recencyScore: 0,
    timeScore: 0,
    priorityScore: 5,
    priorityRank: 1,
    reasonCodes: [],
    ...overrides,
  }
}

function day(overrides: Partial<AttemptTrendDay>): AttemptTrendDay {
  return {
    day: "2026-08-29",
    total: 4,
    correct: 2,
    wrong: 1,
    blank: 0,
    passTimeout: 0,
    successRate: 50,
    avgTimeMs: 2125,
    ...overrides,
  }
}

describe("StudentAnalytics", () => {
  it("veri yoksa anlasilir empty state gosterir", () => {
    render(<StudentAnalytics priorities={[]} trend7={[]} trend30={[]} />)
    expect(
      screen.getByRole("heading", { name: "Henüz yeterli veri yok" })
    ).toBeInTheDocument()
    expect(
      screen.getByText(/Henüz yeterli çözüm verin yok/)
    ).toBeInTheDocument()
  })

  it("güclu konulari ayri gosterir ve zayif olarak isaretlemez", () => {
    render(
      <StudentAnalytics
        priorities={[topic({ topicName: "Rasyonel Sayılar" })]}
        trend7={[]}
        trend30={[]}
      />
    )
    expect(
      screen.getByRole("heading", { name: "Güçlü konular" })
    ).toBeInTheDocument()
    expect(screen.getAllByText("Rasyonel Sayılar").length).toBeGreaterThan(0)
    expect(screen.queryByText(/Öncelikli konular/)).not.toBeInTheDocument()
  })

  it("gelisen konulari ayri gosterir", () => {
    render(
      <StudentAnalytics
        priorities={[
          topic({
            topicName: "Kümeler",
            performanceBand: "DEVELOPING",
          }),
        ]}
        trend7={[]}
        trend30={[]}
      />
    )
    expect(
      screen.getByRole("heading", { name: "Gelişen konular" })
    ).toBeInTheDocument()
  })

  it("oncelikli (WEAK) konulari puanla gosterir", () => {
    render(
      <StudentAnalytics
        priorities={[
          topic({
            topicName: "Türev",
            performanceBand: "WEAK",
            priorityScore: 72,
            successRate: 30,
            lastAttemptedAt: "2026-08-01T10:00:00.000Z",
          }),
        ]}
        trend7={[]}
        trend30={[]}
      />
    )
    expect(
      screen.getByRole("heading", { name: "Öncelikli konular" })
    ).toBeInTheDocument()
    expect(screen.getAllByText("Türev").length).toBeGreaterThan(0)
    expect(screen.getByText(/Öncelik puanı:/)).toBeInTheDocument()
  })

  it("yetersiz veri konularini 'zayif' diye etiketlemez", () => {
    render(
      <StudentAnalytics
        priorities={[
          topic({
            topicName: "Denklemler",
            performanceBand: "INSUFFICIENT_DATA",
            totalAttempts: 2,
          }),
        ]}
        trend7={[]}
        trend30={[]}
      />
    )
    expect(
      screen.getByRole("heading", { name: "Daha fazla veri beklenen konular" })
    ).toBeInTheDocument()
    expect(screen.queryByText(/Öncelikli konular/)).not.toBeInTheDocument()
    expect(screen.getByText("Denklemler")).toBeInTheDocument()
  })

  it("neden kodlarini kullanici diline cevirir", () => {
    render(
      <StudentAnalytics
        priorities={[
          topic({
            topicName: "Türev",
            performanceBand: "WEAK",
            reasonCodes: ["LOW_SUCCESS", "LOW_REPEAT_SUCCESS", "STALE_TOPIC"],
          }),
        ]}
        trend7={[]}
        trend30={[]}
      />
    )
    expect(screen.getByText("Başarı oranı düşük")).toBeInTheDocument()
    expect(screen.getByText("Tekrarlarda zorlanıyor")).toBeInTheDocument()
    expect(screen.getByText("Uzun süredir çalışılmadı")).toBeInTheDocument()
  })

  it("'Bugün ne çalışmalıyım?' yalniz islem yapilabilir konulari gosterir", () => {
    render(
      <StudentAnalytics
        priorities={[
          topic({
            topicName: "Zayıf Konu",
            performanceBand: "WEAK",
            priorityScore: 90,
          }),
          topic({
            topicName: "Verisiz Konu",
            performanceBand: "INSUFFICIENT_DATA",
            priorityScore: 99,
          }),
        ]}
        trend7={[]}
        trend30={[]}
      />
    )
    expect(
      screen.getByRole("heading", { name: "Bugün ne çalışmalıyım?" })
    ).toBeInTheDocument()
    const todaySection = screen
      .getByRole("heading", { name: "Bugün ne çalışmalıyım?" })
      .closest("section") as HTMLElement
    expect(within(todaySection).getByText("Zayıf Konu")).toBeInTheDocument()
    expect(
      within(todaySection).queryByText("Verisiz Konu")
    ).not.toBeInTheDocument()
  })

  it("7/30 gun trend ozetini gosterir", () => {
    render(
      <StudentAnalytics
        priorities={[]}
        trend7={[day({ total: 10, successRate: 80 })]}
        trend30={[
          day({ total: 10, successRate: 80 }),
          day({ total: 2, successRate: 50 }),
        ]}
      />
    )
    expect(screen.getByRole("heading", { name: "Çözüm özeti" })).toBeInTheDocument()
    expect(screen.getByText("Son 7 gün")).toBeInTheDocument()
    expect(screen.getByText("Son 30 gün")).toBeInTheDocument()
    expect(screen.getAllByText("Çözülen soru").length).toBeGreaterThan(0)
  })

  it("semantik basliklar ve tarih gösterimi", () => {
    render(
      <StudentAnalytics
        priorities={[
          topic({
            topicName: "Kümeler",
            performanceBand: "STRONG",
            lastAttemptedAt: "2026-08-12T10:00:00.000Z",
          }),
        ]}
        trend7={[]}
        trend30={[]}
      />
    )
    expect(
      screen.getByText("Son çalışma: 12.08.2026")
    ).toBeInTheDocument()
    expect(screen.getByRole("heading", { name: "Güçlü konular" })).toBeInTheDocument()
  })
})
