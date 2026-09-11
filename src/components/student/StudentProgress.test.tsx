import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import StudentProgress, {
  buildProgressView,
  formatLastUpdate,
} from "./StudentProgress"
import type { DimensionSummaryRow } from "@/lib/analytics/types"

function row(overrides: Partial<DimensionSummaryRow>): DimensionSummaryRow {
  return {
    scopeType: "topic",
    scopeKey: "cccccccc-0000-0000-0000-000000000001",
    displayName: "Kesirler",
    subjectId: "bbbbbbbb-0000-0000-0000-000000000001",
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

describe("buildProgressView — DTO gruplama ve bandlar", () => {
  it("ders/konu/kazanım satırlarını ayrıştırır ve bandları mevcut eşiklerle üretir", () => {
    const view = buildProgressView([
      row({ scopeType: "subject", displayName: "Matematik", successRate: 80 }),
      row({ scopeType: "topic", displayName: "Kesirler", successRate: 80 }),
      row({
        scopeType: "outcome",
        scopeKey: "dddddddd-0000-0000-0000-000000000001",
        displayName: "Kesirleri karşılaştırır",
        total: 10,
        successRate: 85,
      }),
      row({
        scopeType: "outcome",
        scopeKey: "dddddddd-0000-0000-0000-000000000002",
        displayName: "Ondalık yazma",
        total: 6,
        successRate: 33.3,
      }),
      row({
        scopeType: "outcome",
        scopeKey: "dddddddd-0000-0000-0000-000000000003",
        displayName: "Üslü ifadeler",
        total: 2,
        successRate: 50,
      }),
    ])

    expect(view.subjects).toHaveLength(1)
    expect(view.subjects[0]).toMatchObject({
      subjectName: "Matematik",
      total: 10,
      correct: 8,
      wrong: 2,
    })
    expect(view.topics).toHaveLength(1)
    expect(view.topics[0].band).toBe("STRONG")
    expect(view.strongOutcomes.map((o) => o.name)).toEqual([
      "Kesirleri karşılaştırır",
    ])
    expect(view.improvingOutcomes.map((o) => o.name)).toEqual([
      "Ondalık yazma",
    ])
    expect(view.improvingOutcomes[0].band).toBe("WEAK")
    // 2 deneme < MIN_BAND_ATTEMPTS: kanıt yetersiz, geliştirme listesine girmez.
    expect(view.insufficientOutcomeCount).toBe(1)
    // Genel özet mevcut computeOutcomeProgress sözleşmesini kullanır.
    expect(view.overview).toMatchObject({
      total: 3,
      withEvidence: 3,
      mastered: 1,
      weak: 1,
      developing: 1,
      insufficient: 0,
    })
  })

  it("boş satır listesinde tüm listeler boş ve overview null olur", () => {
    const view = buildProgressView([])

    expect(view.overview).toBeNull()
    expect(view.subjects).toHaveLength(0)
    expect(view.topics).toHaveLength(0)
    expect(view.outcomes).toHaveLength(0)
    expect(view.lastAttemptedAt).toBeNull()
  })

  it("son çalışma zamanını satırların en büyüğünden türetir", () => {
    const view = buildProgressView([
      row({ lastAttemptedAt: "2026-09-01T10:00:00.000Z" }),
      row({
        scopeKey: "cccccccc-0000-0000-0000-000000000002",
        lastAttemptedAt: "2026-09-05T10:00:00.000Z",
      }),
    ])

    expect(view.lastAttemptedAt).toBe("2026-09-05T10:00:00.000Z")
  })
})

describe("formatLastUpdate", () => {
  it("geçerli ISO'yu tr-TR etiketine çevirir; bozuğu null'a düşürür", () => {
    expect(formatLastUpdate(null)).toBeNull()
    expect(formatLastUpdate("bozuk-tarih")).toBeNull()
    const label = formatLastUpdate("2026-09-05T10:00:00.000Z")
    expect(label).toBeTruthy()
    expect(label).toMatch(/2026/)
  })
})

describe("StudentProgress — render durumları", () => {
  it("başlık, genel özet, ders konu kazanım bölümleri ve tekrar bağlantısını render eder", () => {
    render(
      <StudentProgress
        rows={[
          row({
            scopeType: "subject",
            displayName: "Matematik",
            lastAttemptedAt: "2026-09-05T10:00:00.000Z",
          }),
          row({ scopeType: "topic", displayName: "Kesirler" }),
          row({
            scopeType: "outcome",
            scopeKey: "dddddddd-0000-0000-0000-000000000001",
            displayName: "Kesirleri karşılaştırır",
            total: 10,
            successRate: 85,
          }),
          row({
            scopeType: "outcome",
            scopeKey: "dddddddd-0000-0000-0000-000000000002",
            displayName: "Ondalık yazma",
            total: 6,
            successRate: 33.3,
          }),
        ]}
        error={null}
      />
    )

    expect(
      screen.getByRole("heading", { level: 1, name: "İlerlemen" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("heading", { name: "Genel Kazanım Özeti" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("heading", { name: "Ders Bazında İlerleme" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("heading", { name: "Konu Bazında İlerleme" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("heading", { name: "Güçlü Kazanımların" })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("heading", { name: "Geliştirilecek Kazanımların" })
    ).toBeInTheDocument()

    // Sunucu sözleşmesinden gelen değerler görünür (dersten türetilen satır).
    const subjectItem = screen.getByText("Matematik").closest("li")
    expect(subjectItem?.textContent).toContain(
      "10 cevaplanan · 8 doğru · 2 yanlış"
    )

    // Hedefli tekrar bağlantıları güvenli sabit rotalara gider.
    const analytLink = screen.getByRole("link", {
      name: /Kazanım analitiğini gör/,
    })
    expect(analytLink).toHaveAttribute(
      "href",
      "/tekrar/bbbbbbbb-0000-0000-0000-000000000001"
    )
    expect(
      screen.getByRole("link", { name: /Hedefli tekrara geç/ })
    ).toHaveAttribute("href", "/tekrar")

    // Son çalışma bilgisi yalnız güvenilir alandan gelir.
    expect(screen.getByText(/Son çalışma:/)).toBeInTheDocument()
  })

  it("boş veride çalışmaya yönlendiren boş durum gösterir", () => {
    render(<StudentProgress rows={[]} error={null} />)

    expect(screen.getByText("Henüz çalışma verisi yok")).toBeInTheDocument()
    expect(
      screen.getByRole("link", { name: /Antrenmana başla/ })
    ).toHaveAttribute("href", "/training")
    expect(
      screen.queryByRole("heading", { name: "Ders Bazında İlerleme" })
    ).toBeNull()
  })

  it("hata durumunda ham hata sızmaz, güvenli Türkçe mesaj görünür", () => {
    render(
      <StudentProgress
        rows={[]}
        error="Kimlik doğrulaması doğrulanamadı."
      />
    )

    expect(
      screen.getByText(/İlerlemen şu anda yüklenemedi/)
    ).toBeInTheDocument()
    expect(
      screen.queryByText("Henüz çalışma verisi yok")
    ).toBeNull()
  })

  it("kazanım verisi olup konu verisi olmayan derste hazırlanıyor durumu görünür", () => {
    render(
      <StudentProgress
        rows={[row({ scopeType: "subject", displayName: "Matematik" })]}
        error={null}
      />
    )

    expect(screen.getByText(/İçerikler hazırlanıyor/)).toBeInTheDocument()
  })

  it("güçlü kazanımı olmayan öğrenciye güvenli boş metin gösterir", () => {
    render(
      <StudentProgress
        rows={[
          row({
            scopeType: "outcome",
            displayName: "Ondalık yazma",
            total: 6,
            successRate: 33.3,
          }),
        ]}
        error={null}
      />
    )

    expect(
      screen.getByText(/Henüz %70 ve üzeri başarıya ulaşmış kazanımın yok/)
    ).toBeInTheDocument()
  })
})
