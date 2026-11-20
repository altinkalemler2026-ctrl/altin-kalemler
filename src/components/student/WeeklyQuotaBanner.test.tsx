/**
 * 163 haftalik kota gostergesi testleri (AK-MEB-VAULT-42-22).
 *
 * - Selector: 0/40 bos, 40/40 dolu, 195/200 (5 hak var → acik),
 *   198/200 (2 hak → kapali), 200/200 kapali.
 * - Teknik durumlar (donem yok / veri yok) kilitlemez, sayi gostermez.
 * - Banner: gercek sayilar + kota-tukenmis tam urun mesaji.
 */

import { cleanup, render, screen } from "@testing-library/react"
import { afterEach, describe, expect, it } from "vitest"

import {
  subjectQuotaBlocksJoin,
  subjectQuotaCompetitionsRemaining,
  subjectQuotaNewQuestionsRemaining,
  weeklyQuotaBlocksJoin,
  weeklyQuotaCompetitionsRemaining,
  weeklyQuotaNewQuestionsRemaining,
  type SubjectWeeklyQuotaSnapshot,
  type SubjectWeeklyQuotaStatus,
  type WeeklyQuotaStatus,
} from "@/lib/competition/types"
import WeeklyQuotaBanner from "./WeeklyQuotaBanner"

function quota(overrides: Partial<WeeklyQuotaStatus> = {}): WeeklyQuotaStatus {
  return {
    academicYear: "2026-2027",
    week: 9,
    competitionsUsed: 0,
    competitionsLimit: 40,
    newQuestionsUsed: 0,
    newQuestionsLimit: 200,
    ...overrides,
  }
}

const QUOTA_MESSAGE =
  "Haftalık yarışma hakkınız tükendi. Yeni haftanın başlamasıyla birlikte tekrar yarışmalara katılabilirsiniz."

afterEach(() => {
  cleanup()
})

describe("weeklyQuotaBlocksJoin — kota sinirlari", () => {
  it("0/40 baslangic: bloklu degil", () => {
    expect(weeklyQuotaBlocksJoin(quota())).toBe(false)
  })

  it("40/40 yarisma dolulugu: bloklu", () => {
    expect(
      weeklyQuotaBlocksJoin(quota({ competitionsUsed: 40 }))
    ).toBe(true)
  })

  it("39/40: henuz bloklu degil (bir hak var)", () => {
    expect(
      weeklyQuotaBlocksJoin(quota({ competitionsUsed: 39 }))
    ).toBe(false)
  })

  it("195/200 yeni soru: kalan 5 → bloklu degil (bes soruluk paket var)", () => {
    expect(
      weeklyQuotaBlocksJoin(quota({ newQuestionsUsed: 195 }))
    ).toBe(false)
    expect(weeklyQuotaNewQuestionsRemaining(quota({ newQuestionsUsed: 195 }))).toBe(5)
  })

  it("198/200 yeni soru: kalan 2 → bloklu (bes soruluk hak yok)", () => {
    expect(
      weeklyQuotaBlocksJoin(quota({ newQuestionsUsed: 198 }))
    ).toBe(true)
  })

  it("200/200 yeni soru dolulugu: bloklu", () => {
    expect(
      weeklyQuotaBlocksJoin(quota({ newQuestionsUsed: 200 }))
    ).toBe(true)
  })

  it("kalanlar negatif'e dusmez (limit asilsa bile)", () => {
    const q = quota({ competitionsUsed: 45, newQuestionsUsed: 250 })
    expect(weeklyQuotaCompetitionsRemaining(q)).toBe(0)
    expect(weeklyQuotaNewQuestionsRemaining(q)).toBe(0)
  })

  it("teknik durumlar kilitlemez: null / donem yok", () => {
    expect(weeklyQuotaBlocksJoin(null)).toBe(false)
    expect(
      weeklyQuotaBlocksJoin(quota({ academicYear: null, week: null }))
    ).toBe(false)
  })

  it("hafta degisimi: her hafta kendi taze DTO'suyla bagimsiz degerlendirilir", () => {
    const w8Dolu = quota({ week: 8, competitionsUsed: 40 })
    const w9Bos = quota({ week: 9, competitionsUsed: 0 })
    expect(weeklyQuotaBlocksJoin(w8Dolu)).toBe(true)
    // Yeni hafta sunucudan yeni (bos) satirla gelir → blok kalkar.
    expect(weeklyQuotaBlocksJoin(w9Bos)).toBe(false)
  })
})

describe("WeeklyQuotaBanner — gosterim", () => {
  it("gercek sayilari ve kalan haklari gosterir", () => {
    render(<WeeklyQuotaBanner quota={quota({ competitionsUsed: 12, newQuestionsUsed: 47 })} />)

    expect(screen.getByText(/12\/40/)).toBeDefined()
    expect(screen.getByText(/47\/200/)).toBeDefined()
    expect(screen.getByText(/28 yarışma hakkın kaldı/)).toBeDefined()
    expect(screen.getByText(/153 yeni soru hakkın kaldı/)).toBeDefined()
    expect(
      screen.queryByText(/haftalık yarışma hakkınız tükendi/i)
    ).toBeNull()
  })

  it("0/40 baslangicta tum haklar görunur", () => {
    render(<WeeklyQuotaBanner quota={quota()} />)
    expect(screen.getByText(/0\/40/)).toBeDefined()
    expect(screen.getByText(/40 yarışma hakkın kaldı/)).toBeDefined()
    expect(screen.getByText(/200 yeni soru hakkın kaldı/)).toBeDefined()
  })

  it("40/40 dolulukta tam urun mesaji gosterilir", () => {
    render(<WeeklyQuotaBanner quota={quota({ competitionsUsed: 40 })} />)
    expect(screen.getByRole("status").textContent).toBe(QUOTA_MESSAGE)
  })

  it("198/200'de de ayni kota mesaji gosterilir", () => {
    render(<WeeklyQuotaBanner quota={quota({ newQuestionsUsed: 198 })} />)
    expect(screen.getByRole("status").textContent).toBe(QUOTA_MESSAGE)
  })

  it("donem yoksa (teknik durum) HICBIR sayi gosterilmez", () => {
    const { container } = render(
      <WeeklyQuotaBanner quota={quota({ academicYear: null, week: null })} />
    )
    expect(container.innerHTML).toBe("")
  })

  it("kota verisi yoksa (RPC teknigi hata) hicbir sey gosterilmez", () => {
    const { container } = render(<WeeklyQuotaBanner quota={null} />)
    expect(container.innerHTML).toBe("")
  })
})

// ------------------------------------------------------------
// 165 ders bazli mod (AK-QUOTA-SUBJECT-01)
// ------------------------------------------------------------

describe("WeeklyQuotaBanner — 165 ders bazli mod", () => {
  const snapshot: SubjectWeeklyQuotaSnapshot = {
    academicYear: "2026-2027",
    week: 9,
    subjects: [
      {
        subjectId: "11111111-1111-4111-8111-111111111111",
        competitionsUsed: 40,
        competitionsLimit: 40,
        newQuestionsUsed: 200,
        newQuestionsLimit: 200,
      },
    ],
  }

  it("snapshot verildiginde kuresel sayi GOSTERILMEZ (sayilar kartlardadir)", () => {
    render(
      <WeeklyQuotaBanner quota={quota({ competitionsUsed: 12 })} subjectSnapshot={snapshot} />
    )
    // Kuresel "Yarışma: 12/40" satiri uydurulmaz:
    expect(screen.queryByText(/Yarışma: 12\/40/)).toBeNull()
    // Model bilgisi gosterilir:
    expect(
      screen.getByText(/Her dersten haftada en fazla 40 yarışma ve 200 yeni soru/)
    ).toBeInTheDocument()
  })

  it("ders bazli modda donem yoksa HICBIR sey gosterilmez", () => {
    const { container } = render(
      <WeeklyQuotaBanner
        quota={null}
        subjectSnapshot={{ academicYear: null, week: null, subjects: [] }}
      />
    )
    expect(container.innerHTML).toBe("")
  })

  it("snapshot null ise kuresel 163 gosterimi aynen durur", () => {
    render(
      <WeeklyQuotaBanner quota={quota({ competitionsUsed: 40 })} subjectSnapshot={null} />
    )
    expect(screen.getByText(/Yarışma: 40\/40/)).toBeInTheDocument()
  })
})

// ------------------------------------------------------------
// 165 ders bazli selector sinirlari (subjectQuotaBlocksJoin)
// ------------------------------------------------------------

describe("subjectQuotaBlocksJoin — ders bazli sinirlar", () => {
  const q = (
    overrides: Partial<SubjectWeeklyQuotaStatus> = {}
  ): SubjectWeeklyQuotaStatus => ({
    subjectId: "11111111-1111-4111-8111-111111111111",
    competitionsUsed: 0,
    competitionsLimit: 40,
    newQuestionsUsed: 0,
    newQuestionsLimit: 200,
    ...overrides,
  })

  it("veri yoksa (null) KILITLEMEZ — sunucu gercek kapidir", () => {
    expect(subjectQuotaBlocksJoin(null)).toBe(false)
  })

  it("0/40 baslangic: bloklu degil", () => {
    expect(subjectQuotaBlocksJoin(q())).toBe(false)
  })

  it("40/40 yarisma dolulugu: bloklu", () => {
    expect(subjectQuotaBlocksJoin(q({ competitionsUsed: 40 }))).toBe(true)
  })

  it("39/40: bloklu degil (bir hak var)", () => {
    expect(subjectQuotaBlocksJoin(q({ competitionsUsed: 39 }))).toBe(false)
  })

  it("195/200 yeni soru: kalan 5 → bloklu degil; 196/200 → bloklu", () => {
    expect(subjectQuotaBlocksJoin(q({ newQuestionsUsed: 195 }))).toBe(false)
    expect(subjectQuotaBlocksJoin(q({ newQuestionsUsed: 196 }))).toBe(true)
  })

  it("ayri ders bagimsizdir: Matematik 40/40 iken Fizik 0/40 acik kalir", () => {
    expect(
      subjectQuotaBlocksJoin(q({ competitionsUsed: 40 })) // Matematik
    ).toBe(true)
    expect(subjectQuotaBlocksJoin(q({ competitionsUsed: 0 }))) // Fizik
      .toBe(false)
  })

  it("kalanlar negatif olmaya inmez (Math.max 0)", () => {
    const full = q({ competitionsUsed: 40, newQuestionsUsed: 200 })
    expect(subjectQuotaCompetitionsRemaining(full)).toBe(0)
    expect(subjectQuotaNewQuestionsRemaining(full)).toBe(0)
  })
})
