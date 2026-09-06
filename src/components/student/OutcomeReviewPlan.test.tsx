/**
 * OutcomeReviewPlan testleri (Faz 6 kazanım analitiği kartları).
 *
 * - Bant grupları: Öncelikli / Geliştirilecek / Güçlü / Yeterli veri
 * - Yetersiz veride yüzde YOK; açıklayıcı metin VAR
 * - Tekrar etkisi: redeem_rate yalnız non-null iken gösterilir
 * - Tekrar başlat bağlantısı YALNIZ weak/developing + bekleyen hatası
 *   olan kazanımlarda görünür
 * - Veri yoksa boş durum açıklayıcıdır
 */

import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import OutcomeReviewPlan from "./OutcomeReviewPlan"
import type { OutcomeReviewRow } from "@/lib/review/types"

const SUBJECT_ID = "430903f3-527e-4e12-b7e8-ac0afdb784aa"

function row(overrides: Partial<OutcomeReviewRow> = {}): OutcomeReviewRow {
  return {
    outcomeId: "22222222-2222-4222-8222-000000000001",
    outcomeText: "Kesirlerle toplama yapar",
    band: "weak",
    totalAttempts: 12,
    successRate: 33.3,
    repeatTotal: 4,
    repeatSuccessRate: 50,
    pendingErrors: 3,
    redeemed: 2,
    redeemRate: 40,
    lastReviewedAt: null,
    ...overrides,
  }
}

describe("OutcomeReviewPlan", () => {
  it("bant gruplarını başlıklarıyla render eder", () => {
    render(
      <OutcomeReviewPlan
        subjectId={SUBJECT_ID}
        subjectName="Matematik"
        rows={[
          row({ outcomeText: "Zayıf kazanım" }),
          row({
            outcomeId: "22222222-2222-4222-8222-000000000002",
            outcomeText: "Gelişen kazanım",
            band: "developing",
            successRate: 55,
            redeemRate: null,
          }),
          row({
            outcomeId: "22222222-2222-4222-8222-000000000003",
            outcomeText: "Güçlü kazanım",
            band: "strong",
            successRate: 90,
            pendingErrors: 0,
            redeemRate: null,
          }),
          row({
            outcomeId: "22222222-2222-4222-8222-000000000004",
            outcomeText: "Verisiz kazanım",
            band: "insufficient_data",
            totalAttempts: 2,
            successRate: null,
            pendingErrors: 0,
            redeemRate: null,
          }),
        ]}
      />
    )

    expect(screen.getByText("Öncelikli kazanımlar")).toBeInTheDocument()
    expect(screen.getByText("Geliştirilecek kazanımlar")).toBeInTheDocument()
    expect(screen.getByText("Güçlü kazanımlar")).toBeInTheDocument()
    expect(
      screen.getByText("Yeterli veri beklenen kazanımlar")
    ).toBeInTheDocument()

    expect(screen.getByText("Zayıf kazanım")).toBeInTheDocument()
    expect(screen.getByText("Gelişen kazanım")).toBeInTheDocument()
    expect(screen.getByText("Güçlü kazanım")).toBeInTheDocument()
    expect(screen.getByText("Verisiz kazanım")).toBeInTheDocument()
  })

  it("yetersiz veride yüzde GÖSTERMEZ; açıklayıcı metin verir", () => {
    render(
      <OutcomeReviewPlan
        subjectId={SUBJECT_ID}
        subjectName="Matematik"
        rows={[
          row({
            outcomeText: "Verisiz kazanım",
            band: "insufficient_data",
            totalAttempts: 2,
            successRate: null,
            pendingErrors: 0,
            redeemRate: null,
          }),
        ]}
      />
    )

    expect(screen.getByText(/yeterli veri yok/)).toBeInTheDocument()
    expect(
      screen.getAllByText(/henüz yeterli çözüm verisi yok/).length
    ).toBeGreaterThan(0)
    expect(screen.queryByText(/%[0-9]/)).not.toBeInTheDocument()
    expect(screen.queryByRole("link", { name: /Tekrar başlat/ })).toBeNull()
  })

  it("tekrar etkisi yalnız redeem_rate non-null iken gösterilir", () => {
    render(
      <OutcomeReviewPlan
        subjectId={SUBJECT_ID}
        subjectName="Matematik"
        rows={[
          row({ outcomeText: "Telafi ölçülebilir" }),
          row({
            outcomeId: "22222222-2222-4222-8222-000000000005",
            outcomeText: "Telafi ölçülemez",
            band: "developing",
            successRate: 55,
            pendingErrors: 2,
            redeemed: 1,
            redeemRate: null,
          }),
        ]}
      />
    )

    expect(screen.getByText(/telafi %40/)).toBeInTheDocument()
    expect(
      screen.getByText(/tekrar etkisi için yeterli veri yok/)
    ).toBeInTheDocument()
  })

  it("Tekrar başlat yalnız bekleyen hatası olan weak/developing kazanımdadır", () => {
    render(
      <OutcomeReviewPlan
        subjectId={SUBJECT_ID}
        subjectName="Matematik"
        rows={[
          row({ outcomeText: "Zayıf kazanim" }),
          row({
            outcomeId: "22222222-2222-4222-8222-000000000002",
            outcomeText: "Gelişen kazanim",
            band: "developing",
            successRate: 55,
            pendingErrors: 0,
            redeemed: 4,
            redeemRate: null,
          }),
          row({
            outcomeId: "22222222-2222-4222-8222-000000000003",
            outcomeText: "Güçlü kazanim",
            band: "strong",
            successRate: 90,
            pendingErrors: 1,
            redeemRate: null,
          }),
        ]}
      />
    )

    const links = screen
      .getAllByRole("link", { name: /Tekrar başlat/ })
      .map((link) => link.getAttribute("href"))

    expect(links).toEqual([
      `/tekrar/${SUBJECT_ID}?outcome=22222222-2222-4222-8222-000000000001`,
    ])
  })

  it("veri yoksa açıklayıcı boş durum verir", () => {
    render(
      <OutcomeReviewPlan
        subjectId={SUBJECT_ID}
        subjectName="Matematik"
        rows={[]}
      />
    )

    expect(
      screen.getByText("Henüz tekrar verisi yok")
    ).toBeInTheDocument()
    expect(
      screen.getByRole("link", { name: /Antrenmana başla/ })
    ).toHaveAttribute("href", "/training")
  })
})
