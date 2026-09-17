/**
 * video-pipeline testleri.
 *
 * - Sağlayıcı yapılandırılmadıysa hiçbir aşama "başarılı" sayılmaz;
 *   sahte başarı üretilmez.
 * - Çözüm doğrulaması geçmeyen girdiyle hat çalışmaz.
 * - Tutarlılık denetimi adım-çözüm-şık bağını denetler.
 * - Çözüm sürümü içerik hash'ine bağlıdır (deterministik).
 * - Gerçek ses/video çağrısı YOKTUR; FakeVideoSolutionProvider deterministik.
 */

import { describe, expect, it } from "vitest"

import type { WrittenSolution } from "./solution-types"
import {
  auditVideoConsistency,
  buildSolutionVersion,
  FakeVideoSolutionProvider,
  runVideoPipeline,
  solutionReadyForVideo,
} from "./video-pipeline"

function writtenSolution(): WrittenSolution {
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

function fullContext(
  overrides: Partial<{
    questionText: string
    correctAnswer: string
    writtenSolution: WrittenSolution
    solutionVersion: string
  }> = {}
) {
  return {
    questionText: "3/4 + 1/2 işleminin sonucu kaçtır?",
    correctAnswer: "B",
    writtenSolution: writtenSolution(),
    solutionVersion: buildSolutionVersion(writtenSolution()),
    ...overrides,
  }
}

describe("FakeVideoSolutionProvider — yapılandırma sözleşmesi", () => {
  it("configured=false sağlayıcı hiçbir artefakt üretmez", async () => {
    const provider = new FakeVideoSolutionProvider(false)
    expect(provider.configured).toBe(false)

    await expect(provider.generateNarration(fullContext())).rejects.toThrow(
      "yapılandırılmadı"
    )
    await expect(provider.renderVideo(fullContext())).rejects.toThrow(
      "yapılandırılmadı"
    )
  })

  it("configured=true deterministik artefakt üretir (AI çağrısı yok)", async () => {
    const provider = new FakeVideoSolutionProvider(true)
    const narration = await provider.generateNarration(fullContext())
    const subtitles = await provider.generateSubtitles(fullContext())
    const video = await provider.renderVideo(fullContext())

    expect(narration.narrationText).toContain("Paydaları eşitle")
    expect(subtitles.length).toBeGreaterThan(0)
    expect(video.videoUrl).toMatch(/^\/assets\/fake-video-/)
  })
})

describe("runVideoPipeline — fail-closed kapılar", () => {
  it("sağlayıcı yapılandırılmadıysa not_started + issues döner", async () => {
    const provider = new FakeVideoSolutionProvider(false)
    const result = await runVideoPipeline(provider, fullContext())

    expect(result.providerConfigured).toBe(false)
    expect(result.stage).toBe("not_started")
    expect(result.readyForStudents).toBe(false)
    expect(result.issues).toContain("saglayici_yapilandirilmadi")
    expect(result.mediaUrls).toEqual([])
  })

  it("yazılı çözüm doğrulaması geçmezse hat başlamaz (sahte başarı yok)", async () => {
    const provider = new FakeVideoSolutionProvider(true)
    const junk: WrittenSolution = {
      method: " ",
      steps: [],
      result: "B",
      correctAnswerJustification: "çünkü cevap B",
    }
    const result = await runVideoPipeline(provider, {
      ...fullContext(),
      writtenSolution: junk,
      solutionVersion: buildSolutionVersion(junk),
    })

    expect(result.stage).toBe("not_started")
    expect(result.readyForStudents).toBe(false)
    expect(result.mediaUrls).toEqual([])
    expect(result.issues.length).toBeGreaterThan(0)
  })

  it("geçerli çözüm + yapılandırılmış sağlayıcı human_publish aşamasına ulaşır", async () => {
    const provider = new FakeVideoSolutionProvider(true)
    const result = await runVideoPipeline(provider, fullContext())

    expect(result.stage).toBe("human_publish")
    expect(result.readyForStudents).toBe(true)
    expect(result.issues).toEqual([])
    expect(result.mediaUrls.length).toBe(2)
  })

  it("cevap harfi geçersizse başlamaz", async () => {
    const provider = new FakeVideoSolutionProvider(true)
    const result = await runVideoPipeline(provider, {
      ...fullContext(),
      correctAnswer: "F",
    })
    expect(result.issues).toContain("gecersiz_cevap_harfi")
    expect(result.readyForStudents).toBe(false)
  })
})

describe("auditVideoConsistency — adım/şık bağı", () => {
  const base = {
    storyboardText: "1. Paydaları eşitle: ...\n2. Payları topla: ...",
    narrationText: "Paydaları eşitleyerek toplama yapılır.",
    correctAnswer: "B",
    steps: writtenSolution().steps,
  }

  it("tutarlı ise passed + issue yok", () => {
    const audit = auditVideoConsistency(base)
    expect(audit.passed).toBe(true)
    expect(audit.issues).toEqual([])
  })

  it("sahne adımlarla eşleşmiyorsa tutarsız", () => {
    const audit = auditVideoConsistency({
      ...base,
      storyboardText: "Belirsiz bir metin; adım başlıkları anılmıyor.",
    })
    expect(audit.passed).toBe(false)
    expect(audit.issues).toContain("adim_anlatim_eslesmiyor")
  })

  it("anlatım boşsa tutarsız (fail-closed)", () => {
    const audit = auditVideoConsistency({ ...base, narrationText: " " })
    expect(audit.passed).toBe(false)
    expect(audit.issues).toContain("anlatim_bos")
  })

  it("cevap harfi A-E değilse tutarsız", () => {
    const audit = auditVideoConsistency({ ...base, correctAnswer: "F" })
    expect(audit.passed).toBe(false)
    expect(audit.issues).toContain("gecersiz_cevap_harfi")
  })
})

describe("buildSolutionVersion — içerik sürümü", () => {
  it("içerik değişince sürüm değişir; aynı içerik aynı sürüm", () => {
    const a = writtenSolution()
    const b = writtenSolution()
    const changed = { ...a, method: "Farklı yöntemle çözülür." }

    const vA = buildSolutionVersion(a)
    const vB = buildSolutionVersion(b)
    const vChanged = buildSolutionVersion(changed)

    expect(vA).toBe(vB)
    expect(vA).not.toBe(vChanged)
    expect(vA).toMatch(/^[0-9a-f]{64}$/)
  })
})

describe("solutionReadyForVideo — yazılı çözüm ön kapısı", () => {
  it("yalnız doğru şık yazan çözüm video hattına giremez", () => {
    const brute: WrittenSolution = {
      method: " ",
      steps: [],
      result: "B",
      correctAnswerJustification: "cevap B",
    }
    expect(solutionReadyForVideo(brute, "B")).toBe(false)
  })

  it("geçerli yapılandırılmış çözüm hatta girebilir", () => {
    expect(solutionReadyForVideo(writtenSolution(), "B")).toBe(true)
  })

  it("cevap harfi geçersizse kabul etmez", () => {
    expect(solutionReadyForVideo(writtenSolution(), "Z")).toBe(false)
  })
})