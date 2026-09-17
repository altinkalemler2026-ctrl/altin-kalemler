/**
 * solution-validator testleri.
 *
 * - Yapısal bütünlük: yöntem/adım/sonuç/gerekçe eksiklikleri.
 * - "Yalnız doğru şık" reddi: kısa gerekçe ve harf+adım < 2 durumları.
 * - Determinizm: aynı çözüm → aynı reasons listesi.
 */

import { describe, expect, it } from "vitest"

import {
  computeValidationStatus,
  hasMeaningfulJustification,
  solutionReachesAnswer,
  STEP_CONTENT_MIN_LENGTH,
  validateWrittenSolution,
} from "./solution-validator"
import type { WrittenSolution } from "./solution-types"

function validSolution(): WrittenSolution {
  return {
    method: "Paydaları eşitleyerek toplama yaparız.",
    steps: [
      { title: "Paydaları eşitle", content: "3/4 ve 1/2 kesirlerini sırasıyla 3/4 ve 2/4 olarak yazarız." },
      { title: "Payları topla", content: "3 + 2 = 5 bulunur; payda 4 kalır." },
    ],
    result: "Sonuç 5/4'tür, cevap B seçeneğidir.",
    correctAnswerJustification:
      "Paydalar eşitlendikten sonra paylar toplanır ve sonuç 5/4 bulunur; bu beş şıkkın içinde yalnız B şıkkına karşılık gelir.",
  }
}

describe("validateWrittenSolution — yapısal bütünlük", () => {
  it("geçerli yapılandırılmış çözüm pass döner", () => {
    const v = validateWrittenSolution(validSolution(), "B")
    expect(v.status).toBe("pass")
    expect(v.reasons).toEqual([])
  })

  it("yöntem eksikse fail döner", () => {
    const v = validateWrittenSolution(validSolution(), "B")
    const broken = { ...validSolution(), method: "  " }
    const r = validateWrittenSolution(broken, "B")
    expect(r.status).toBe("fail")
    expect(r.reasons).toContain("bos_metod")
    expect(v.reasons).not.toContain("bos_metod")
  })

  it("adım yoksa fail döner", () => {
    const r = validateWrittenSolution({ ...validSolution(), steps: [] }, "B")
    expect(r.status).toBe("fail")
    expect(r.reasons).toContain("eksik_adim")
  })

  it("adım içeriği çok kısasa fail döner", () => {
    const r = validateWrittenSolution(
      { ...validSolution(), steps: [{ title: "A", content: "x" }] },
      "B"
    )
    expect(r.status).toBe("fail")
    expect(r.reasons).toContain("kisa_adim_icerigi")
  })

  it("sonuç boşsa fail döner", () => {
    const r = validateWrittenSolution({ ...validSolution(), result: "" }, "B")
    expect(r.status).toBe("fail")
    expect(r.reasons).toContain("bos_sonuc")
  })

  it("gerekçe yoksa/çok kısasa fail döner", () => {
    const short = validateWrittenSolution(
      { ...validSolution(), correctAnswerJustification: "cevap B" },
      "B"
    )
    expect(short.status).toBe("fail")
    expect(short.reasons).toContain("kisa_gerekce")
  })
})

describe("solutionReachesAnswer — 'yalnız doğru şık' reddi", () => {
  it("yalnız şık harfi yazan kısa gerekçe cevaba ulaşmaz", () => {
    const bruteForce: WrittenSolution = {
      method: "Deneyerek bulunur.",
      steps: [{ title: "Salla", content: "Rastgele B işaretlenmiştir." }],
      result: "B",
      correctAnswerJustification: "Çünkü cevap B",
    }
    expect(solutionReachesAnswer(bruteForce, "B")).toBe(false)
    expect(hasMeaningfulJustification(bruteForce)).toBe(false)
  })

  it("iki adım + sonuç + yeterli gerekçe çözüm cevaba ulaşır", () => {
    expect(solutionReachesAnswer(validSolution(), "B")).toBe(true)
  })

  it("adım sayısı birden azsa cevaba ulaşmaz", () => {
    const singleStep: WrittenSolution = {
      ...validSolution(),
      steps: [{ title: "Tek işlem", content: "Toplama yapılır ve sonuç yazılır." }],
    }
    expect(solutionReachesAnswer(singleStep, "B")).toBe(false)
  })

  it("gerekçe yalnız şık harfinden ibaretse cevaba ulaşmaz", () => {
    const letterOnly: WrittenSolution = {
      ...validSolution(),
      correctAnswerJustification: "B",
    }
    expect(solutionReachesAnswer(letterOnly, "B")).toBe(false)
  })

  it("gerekçe kısa ve 'yalnız şık' tarzıysa cevaba ulaşmaz", () => {
    const short: WrittenSolution = {
      ...validSolution(),
      correctAnswerJustification: "Çünkü cevap B",
    }
    expect(solutionReachesAnswer(short, "B")).toBe(false)
  })

  it("harf anılmasa bile yapısal olarak sağlam çözüm cevaba ulaşır", () => {
    const noLetter: WrittenSolution = {
      ...validSolution(),
      correctAnswerJustification:
        "Paydalar eşitlenir ve paylar toplanır; bulunan kesir sonucu soru tekniği gereği seçeneklerin içinde yalnız birinde karşılığını bulur ve derece tamamlanır.",
    }
    expect(solutionReachesAnswer(noLetter, "B")).toBe(true)
  })
})

describe("computeValidationStatus — durum ayrımı", () => {
  it("engel yoksa pass", () => {
    expect(computeValidationStatus([])).toBe("pass")
  })

  it("yapısal eksiklik varsa fail", () => {
    expect(computeValidationStatus(["eksik_adim", "bos_metod"])).toBe("fail")
  })

  it("yalnız yumuşak kuşku kodları varsa needs_review", () => {
    expect(computeValidationStatus(["suphe_kanit_yetersiz"])).toBe("needs_review")
  })
})

describe("determinizm", () => {
  it("aynı girdi aynı reasons listesi üretir", () => {
    const a = validateWrittenSolution(validSolution(), "B").reasons
    const b = validateWrittenSolution(validSolution(), "B").reasons
    expect(a).toEqual(b)
    expect(a.length).toBeLessThanOrEqual(STEP_CONTENT_MIN_LENGTH)
  })
})