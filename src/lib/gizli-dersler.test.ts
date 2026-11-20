import { describe, expect, it } from "vitest"

import { GIZLENEN_DERS_ADLARI, dersGizlenecekMi, dersListesiniFiltrele } from "./gizli-dersler"

describe("gizli-dersler — CURRICULUM-ALL-01 kullanıcı kararı (Geometri/Türkçe gizleme)", () => {
  it("yalnız Geometri ve Türkçe gizlenir", () => {
    expect(GIZLENEN_DERS_ADLARI).toEqual(["Geometri", "Türkçe"])
    expect(dersGizlenecekMi("Geometri")).toBe(true)
    expect(dersGizlenecekMi("Türkçe")).toBe(true)
  })

  it("kanonik hedef dersler gizlenmez", () => {
    expect(dersGizlenecekMi("Matematik")).toBe(false)
    expect(dersGizlenecekMi("Fizik")).toBe(false)
    expect(dersGizlenecekMi("Türk Dili ve Edebiyatı")).toBe(false)
  })

  it("ad benzerliği gizlemeye neden olmaz (birebir eşleşme kuralı)", () => {
    expect(dersGizlenecekMi("Türkçe Dersi")).toBe(false)
    expect(dersGizlenecekMi("geometri")).toBe(false)
    expect(dersGizlenecekMi("Türk Dili ve Edebiyatı Dersi")).toBe(false)
  })

  it("dersListesiniFiltrele gizlenenleri düşürür, sırayı korur", () => {
    const liste = [
      { id: "1", name: "Matematik" },
      { id: "2", name: "Geometri" },
      { id: "3", name: "Fizik" },
      { id: "4", name: "Türkçe" },
    ]
    expect(dersListesiniFiltrele(liste)).toEqual([
      { id: "1", name: "Matematik" },
      { id: "3", name: "Fizik" },
    ])
    expect(dersListesiniFiltrele([])).toEqual([])
  })
})
